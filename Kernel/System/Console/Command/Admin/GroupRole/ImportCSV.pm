# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::GroupRole::ImportCSV;

use strict;
use warnings;

use Text::CSV;
$\ = "\n";

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Group',
);
our $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
our %GroupFullnames;
our %GroupShortnames;

our $CountUnchanged = 0;
our $CountAdd = 0;
our $CountRemove = 0;
our $CountError = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Connect a users to groups.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => "Name of the group_user CSV file.",
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
    my $headers = join(",", "role", "groupname", "permissionkey", "permissionvalue");
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

sub _StoreData {
    my ( $Self, %Param ) = @_;

    for (@{$Self->{Data}}) {
        my ($Role, $Groupname, $PermissionKey, $PermissionValue) = @$_;

        my $GroupID = $Self->_GroupLookupByShortname(Group => $Groupname);
        unless ($GroupID) {
            $Self->PrintError("Invalid groupname $Groupname");
            $CountError++;
            next;
        }

        my $RoleID = $GroupObject->RoleLookup(Role => $Role);
        unless ($RoleID) {
            $Self->PrintError("Invalid role $Role");
            $CountError++;
            next;
        }

        my %RoleList;
        if ($GroupID) {
            %RoleList = $GroupObject->PermissionGroupRoleGet(
                GroupID => $GroupID,
                Type    => $PermissionKey,
            );
        }

        if ($RoleList{$RoleID} && ! $PermissionValue) {
            $CountRemove++;
            if ($Self->{Verbose}) {
                $Self->Print("  removing group $Groupname from role $Role");
            }
            unless ($Self->{DryRun}) {
                $GroupObject->PermissionGroupRoleAdd(
                    GID        => $GroupID,
                    RID        => $RoleID,
                    Permission => {$PermissionKey => $PermissionValue},
                    UserID     => 1,
                );
            }
        } elsif (! $RoleList{$RoleID} && $PermissionValue) {
            $CountAdd++;
            if ($Self->{Verbose}) {
                $Self->Print("  adding group $Groupname to role $Role");
            }
            unless ($Self->{DryRun}) {
                $GroupObject->PermissionGroupRoleAdd(
                    GID        => $GroupID,
                    RID        => $RoleID,
                    Permission => {$PermissionKey => $PermissionValue},
                    UserID     => 1,
                );
            }
        } else {
            $CountUnchanged++;
        }
    }
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->_InitializeGroupLists();
    $Self->{Data} = $Self->_SlurpCSV();
    $Self->_StoreData();
    $Self->Print("$CountUnchanged group-role permission unchanged.") if ($CountUnchanged);
    $Self->Print("$CountAdd group-role permissions added.") if ($CountAdd);
    $Self->Print("$CountRemove group-role permissions removed.") if ($CountRemove);
    $Self->Print("$CountError faulty input lines in file " . $Self->{SourcePath}) if ($CountError);
    return $Self->ExitCodeOk();
}

# Groups do not have to specified with full name.
# The first word of the name is supposedly unique.
sub _InitializeGroupLists {
    my ( $Self, %Param ) = @_;

    my %Groups = $GroupObject->GroupList();
    for my $id (keys %Groups) {
        $GroupFullnames{$Groups{$id}} = $id;
        my @short = split(/ /, $Groups{$id}, 2);
        $GroupShortnames{$short[0]} = $id;
    }
}

sub _GroupLookupByShortname {
    my ( $Self, %Param ) = @_;

    my $Group = $Param{Group};
    die ("Need Group") unless ($Group);

    my $GroupID = $GroupFullnames{$Group};
    return $GroupID if ($GroupID);

    $GroupID = $GroupShortnames{$Group};
    return $GroupID if ($GroupID);
}
1;
