# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::Group::ImportCSV;

use strict;
use warnings;

use Text::CSV;
$\ = "\n";

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Group',
);
our $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
our %ValidStrings = reverse $Kernel::OM->Get('Kernel::System::Valid')->ValidList();

our $CountUnchanged = 0;
our $CountAdd = 0;
our $CountUpdate = 0;
our $CountError = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Import groups from CSV file.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => 'Name of the group CSV file.',
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
    my $headers = join(",", "name", "comments", "validity");
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
    $Self->Print("Reading " . $Self->{SourcePath}) if ($Self->{Verbose});
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

sub _StoreData {
    my ( $Self, %Param ) = @_;

    for (@{$Self->{Data}}) {
        my ($Name, $Comment, $Validity) = @$_;

        my $ValidID = $ValidStrings{$Validity};
        unless ($ValidID) {
            $Self->PrintError("Invalid validity: $Validity");
            $CountError++;
            next;
        }

        my $GroupID = $GroupObject->GroupLookup(Group => $Name);

        if ($GroupID) {
            my %GroupData = $GroupObject->GroupGet(
                ID      => $GroupID,
            );
            if (
                $GroupData{"Name"} eq $Name &&
                $GroupData{"Comment"} eq $Comment &&
                $GroupData{"ValidID"} eq $ValidID
            ) {
                $CountUnchanged++;
            } else {
                $CountUpdate++;
                if ($Self->{Verbose}) {
                    $Self->Print("  updating group $Name");
                }
                unless ($Self->{DryRun}) {
                    $GroupObject->GroupUpdate(
                        ID      => $GroupID,
                        Name    => $Name,
                        Comment => $Comment,
                        ValidID => $ValidID,
                        UserID  => 1,
                    );
                }
            }
        } else {
            $CountAdd++;
            if ($Self->{Verbose}) {
                $Self->Print("  adding group $Name");
            }
            unless ($Self->{DryRun}) {
                $GroupObject->GroupAdd(
                    ID      => $GroupID,
                    Name    => $Name,
                    Comment => $Comment,
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
    $Self->_StoreData();
    $Self->_PrintStatistics(
        ItemName    => "groups",
        Unchanged   => $CountUnchanged,
        Added       => $CountAdd,
        Updated     => $CountUpdate,
        InputErrors => $CountError,
    );
    return $Self->ExitCodeOk();
}
1;
