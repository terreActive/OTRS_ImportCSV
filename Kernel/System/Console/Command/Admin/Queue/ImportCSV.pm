# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::Queue::ImportCSV;

use strict;
use warnings;

use Text::CSV;
$\ = "\n";

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Group',
    'Kernel::System::Queue',
    'Kernel::System::Valid',
);
our $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
our $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
our %GroupFullnames;
our %GroupShortnames;
our %ValidStrings = reverse $Kernel::OM->Get('Kernel::System::Valid')->ValidList();

our $CountUnchanged = 0;
our $CountAdd = 0;
our $CountUpdate = 0;
our $CountError = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Import queues from CSV file');
    $Self->AddOption(
        Name        => 'source-path',
        Description => 'Name of the queue CSV file.',
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
    my $headers = join(",", "name", "group", "comments", "validity");
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
    my $ok = 1;
    for (@{$Self->{Data}}) {
        my $key = $_->[0];
        if ($keys{$key}) {
            $Self->PrintError("Duplicate: $key");
            $ok = 0;
        }
        $keys{$key} = $_->[0];
    }
    return $ok;
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

# copy of Kernel::System::Queue::QueueLookup with Silent parameter
sub _QueueLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Queue} && !$Param{QueueID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no Queue or QueueID!'
        );
        return;
    }

    # get (already cached) queue data
    my %QueueList = $QueueObject->QueueList(
        Valid => 0,
    );

    my $Key;
    my $Value;
    my $ReturnData;
    if ( $Param{QueueID} ) {
        $Key        = 'QueueID';
        $Value      = $Param{QueueID};
        $ReturnData = $QueueList{ $Param{QueueID} };
    }
    else {
        $Key   = 'Queue';
        $Value = $Param{Queue};
        my %QueueListReverse = reverse %QueueList;
        $ReturnData = $QueueListReverse{ $Param{Queue} };
    }

    # check if data exists
    if ( !$ReturnData && !$Param{Silent} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Found no $Key for $Value!",
        );
        return;
    }

    return $ReturnData;
}

sub _StoreData {
    my ( $Self, %Param ) = @_;

    for (@{$Self->{Data}}) {
        my ($Name, $Group, $Comments, $Validity) = @$_;

        my $ValidID = $ValidStrings{$Validity};
        unless ($ValidID) {
            $Self->PrintError("Invalid validity: $Validity");
            $CountError++;
            next;
        }
        my $GroupID = $Self->_GroupLookupByShortname(Group => $Group);
        unless ($GroupID) {
            $Self->PrintError("Invalid Group $Group");
            $CountError++;
            next;
        }

        my $QueueID = $Self->_QueueLookup(Queue => $Name, Silent => 1);

        if ($QueueID) {
            my %QueueData = $QueueObject->QueueGet(
                ID      => $QueueID,
            );
            if (
                $QueueData{"Name"} eq $Name &&
                $QueueData{"GroupID"} eq $GroupID &&
                $QueueData{"Comment"} eq $Comments &&
                $QueueData{"ValidID"} eq $ValidID
            ) {
                $CountUnchanged++;
            } else {
                $CountUpdate++;
                if ($Self->{Verbose}) {
                    $Self->Print("  updating queue $Name($QueueID):");
                    if ($QueueData{"Name"} ne $Name) {
                        $Self->Print("    Name->" . $Name);
                    }
                    if ($QueueData{"GroupID"} ne $GroupID) {
                        $Self->Print("    GroupID->" . $GroupID);
                    }
                    if ($QueueData{"Comment"} ne $Comments) {
                        $Self->Print("    Comment->" . $Comments);
                    }
                    if ($QueueData{"ValidID"} != $ValidID) {
                        $Self->Print("    ValidID->" . $ValidID);
                    }
                }
                unless ($Self->{DryRun}) {
                    $QueueObject->QueueUpdate(
                        QueueID         => $QueueID,
                        Name            => $Name,
                        GroupID         => $GroupID,
                        Comment         => $Comments,
                        ValidID         => $ValidID,
                        SystemAddressID => $QueueData{SystemAddressID},
                        SalutationID    => $QueueData{SalutationID},
                        SignatureID     => $QueueData{SignatureID},
                        FollowUpID      => $QueueData{FollowUpID},
                        UserID          => 1,
                    );
                }
            }
        } else {
            $CountAdd++;
            if ($Self->{Verbose}) {
                $Self->Print("  adding queue $Name");
            }
            unless ($Self->{DryRun}) {
                $QueueObject->QueueAdd(
                    Name    => $Name,
                    GroupID => $GroupID,
                    Comment => $Comments,
                    ValidID => $ValidID,
                    UserID  => 1,
                );
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
        $Self->Print($Param{InputErrors} . " faulty input lines in file " . $Self->{SourcePath});
    }
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->{Data} = $Self->_SlurpCSV();
    $Self->_CheckUnique() or return $Self->ExitCodeError();
    $Self->_InitializeGroupLists();
    $Self->_StoreData();
    $Self->_PrintStatistics(
        ItemName    => "queues",
        Unchanged   => $CountUnchanged,
        Added       => $CountAdd,
        Updated     => $CountUpdate,
        InputErrors => $CountError,
    );
    return $Self->ExitCodeOk();
}
1;
