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

our $CountAdd = 0;
our $CountRemoved = 0;
our $CountError = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Connect users to roles.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => 'Name of the role_user CSV file.',
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
    $Self->AddOption(
        Name        => 'verbose',
        Description => 'Report every updated item',
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
    $Self->{Verbose} = $Self->GetOption('verbose');

    # check file exists
    if ( ! -f $Self->{SourcePath} ) {
        die "File $Self->{SourcePath} does not exist.\n";
    }

    # check header line
    my $headers = join(",", "user", "role", "validity");
    open my $file, '<:encoding(UTF-8)', $Self->{SourcePath};
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
    $Self->Print("Reading CSV file $Self->{SourcePath}...");
    open my $file, '<:encoding(UTF-8)', $Self->{SourcePath};
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
            $CountError++;
            next;
        }
        unless ($_->[1]) {
            $Self->PrintError("Empty role name");
            return $Self->ExitCodeError();
            $CountError++;
            next;
        }
        my $key = $_->[0] . ":" . $_->[1];
        if ($keys{$key} && $keys{$key} ne $_->[2]) {
            $Self->PrintError("Inconsitent Duplicates $key");
            $CountError++;
            next;
        }
        $keys{$key} = $_->[2];
    }
}

sub _StoreData {
    my ( $Self, %Param ) = @_;

    for (@{$Self->{Data}}) {
        my ($User, $Role, $Validity) = @$_;

        my $UserID = $UserObject->UserLookup(UserLogin => $User, Silent => 1);
        unless ($UserID) {
            $Self->PrintError("Invalid user $User");
            $CountError++;
            next;
        }
        my %UserData = $UserObject->GetUserData(UserID => $UserID);
        next unless ($UserData{ValidID} == 1);

        my $RoleID = $GroupObject->RoleLookup(Role => $Role, Silent => 1);
        unless ($RoleID) {
            $Self->Print("Invalid role $Role");
            $CountError++;
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
                $CountRemoved++;
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

sub _PrintStatistics {
    my ( $Self, %Param ) = @_;

    for my $count ("Unchanged", "Added", "Updated", "Removed") {
        if ($Param{$count}) {
            my $message = $Param{$count} . " " . $Param{ItemName} . " ";
            if ($Self->{DryRun}) {
                $message .= "would be "
            }
            $message .= lc($count) . ".";
            $Self->Print($message);
        }
    }
    if ($Param{InputErrors}) {
        $Self->Print($Param{InputErrors} . " errors in " . $Self->{SourcePath});
    }
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->{Data} = $Self->_SlurpCSV();
    $Self->_CheckUnique();
    $Self->_StoreData();
    $Self->_PrintStatistics(
        ItemName    => "user roles",
        Added       => $CountAdd,
        Removed     => $CountRemoved,
        InputErrors => $CountError,
    );
    return $Self->ExitCodeOk();
}
1;
