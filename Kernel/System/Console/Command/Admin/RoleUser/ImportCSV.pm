# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::RoleUser::ImportCSV;

use strict;
use warnings;

use Text::CSV;
$\ = "\n";

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::User',
    'Kernel::System::Group',
);
our $UserObject = $Kernel::OM->Get('Kernel::System::User');
our $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
our $CountMissingUser = 0;
our $CountMissingRole = 0;
our $CountAdd = 0;
our $CountRemove = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Connect a users to roles.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => "Name of the role_user CSV file.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'dry-run',
        Description => 'Test only, do not do any change to the database.',
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {

    my ( $Self, %Param ) = @_;

    $Self->{SourcePath} = $Self->GetOption('source-path');
    $Self->{DryRun} = $Self->GetOption('dry-run');

    # check file exists
    if ( ! -f $Self->{SourcePath} ) {
        die "File $Self->{SourcePath} does not exist.\n";
    }

    # check header line
    my $headers = join(",", "user", "role", "validity");
    open my $file, '<', $Self->{SourcePath};
    my $firstLine = <$file>;
    close $file;
    chomp $firstLine;
    if ($firstLine ne $headers) {
        die "File $Self->{SourcePath} headers are not: $headers.\n";
    }

    return;
}

sub _SlurpCSV() {
    my ( $Self, %Param ) = @_;

    my @Data;
    $Self->Print("<yellow>Reading CSV file $Self->{SourcePath}...</yellow>\n");
    open my $file, '<', $Self->{SourcePath};
    my $csv = Text::CSV->new;
    <$file>; # skip headers
    while (<$file>) {
        $csv->parse($_);
        my @row = $csv->fields();
        push @Data, \@row;
    }
    close $file;
    return \@Data;
}

sub _CheckUnique() {
    my ( $Self, %Param ) = @_;

    my %keys = ();
    my $error = 0;
    for (@{$Self->{Data}}) {
        unless ($_->[0]) {
            $Self->PrintError("Empty user name");
            $error++;
            next;
        }
        unless ($_->[1]) {
            $Self->PrintError("Empty role name");
            return $Self->ExitCodeError();
            $error++;
            next;
        }
        my $key = $_->[0] . ":" . $_->[1];
        if ($keys{$key} && $keys{$key} ne $_->[2]) {
            $Self->PrintError("Inconsitent Duplicates $key");
            return $Self->ExitCodeError();
            $error++;
            next;
        }
        $keys{$key} = $_->[2];
    }
    return $Self->ExitCodeError() if ($error);
}

sub _StoreData {
    my ( $Self, %Param ) = @_;

    for (@{$Self->{Data}}) {
        my ($User, $Role, $Validity) = @$_;

        my $UserID = $UserObject->UserLookup(UserLogin => $User, Silent => 1);
        unless ($UserID) {
            $Self->Print("unknown user $User");
            $CountMissingUser++;
            next;
        }
        my %UserData = $UserObject->GetUserData(UserID => $UserID);
        next unless ($UserData{ValidID} == 1);

        my $RoleID = $GroupObject->RoleLookup(Role => $Role, Silent => 1);
        unless ($RoleID) {
            $Self->Print("unknown role $Role");
            $CountMissingRole++;
            next;
        }
        my %RoleData = $GroupObject->RoleGet(ID => $RoleID);
        next unless ($RoleData{ValidID} == 1);

        unless ($Validity eq "valid" or $Validity eq "invalid") {
            $Self->Print("unknown validity $Validity");
            next;
        }

        my %RoleList = $GroupObject->PermissionUserRoleGet(UserID => $UserID);
        if ($Validity eq "valid") {
            unless (grep {$Role eq $_} values %RoleList) {
                $Self->Print("Adding user $User to role $Role");
                $CountAdd++;
                unless ($Self->{DryRun}) {
                    if ( ! $GroupObject->PermissionRoleUserAdd(
                        UID    => $UserID,
                        RID    => $RoleID,
                        Active => 1,
                        UserID => 1,
                    )) {
                        $Self->PrintError("Can not add user $User to role $Role.");
                        return $Self->ExitCodeError();
                    }
                }
            }
        }
        if ($Validity eq "invalid") {
            if (grep {$Role eq $_} values %RoleList) {
                $Self->Print("Removing user $User from role $Role");
                $CountRemove++;
                unless ($Self->{DryRun}) {
                    if ( ! $GroupObject->PermissionRoleUserAdd(
                        UID    => $UserID,
                        RID    => $RoleID,
                        Active => 0,
                        UserID => 1,
                    )) {
                        $Self->PrintError("Can not delete user $User to role $Role.");
                        return $Self->ExitCodeError();
                    }
                }
            }
        }
    }
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->{Data} = $Self->_SlurpCSV();
    $Self->_CheckUnique();
    $Self->_StoreData() unless $Self->{DryRun};
    $Self->Print("<yellow>$CountMissingUser missing Users.</yellow>\n") if ($CountMissingUser);
    $Self->Print("<yellow>$CountMissingRole missing Roles.</yellow>\n") if ($CountMissingRole);
    $Self->Print("<yellow>$CountAdd links added.</yellow>\n") if ($CountAdd);
    $Self->Print("<yellow>$CountRemove links removed.</yellow>\n") if ($CountRemove);
    return $Self->ExitCodeOk();
}

sub SpareCodeStolen {
    my ( $Self, %Param ) = @_;
    # add user 2 role
    if (
        ! $GroupObject->PermissionRoleUserAdd(
            UID    => $Self->{UserID},
            RID    => $Self->{RoleID},
            Active => 1,
            UserID => 1,
        )
        ) {
        $Self->PrintError("Can't add user to role.");
        return $Self->ExitCodeError();
    }

    $Self->Print("Done.\n");
    return $Self->ExitCodeOk();
}

1;
