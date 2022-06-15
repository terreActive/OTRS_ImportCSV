# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::Service::ImportCSV;

use strict;
use warnings;

use Text::CSV;
$\ = "\n";

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Service',
);
our $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');
our %ValidStrings =
    reverse $Kernel::OM->Get('Kernel::System::Valid')->ValidList();

our $CountUnchanged = 0;
our $CountAdd = 0;
our $CountUpdate = 0;
our $CountError = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Import servicess from CSV file.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => 'Name of the services CSV file.',
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

        my $ServiceID = $ServiceObject->ServiceLookup(Name => $Name);

        if ($ServiceID) {
            my %ServiceData = $ServiceObject->ServiceGet(
                ServiceID => $ServiceID,
                UserID    => 1,
            );
            if (
                $ServiceData{"Comment"} eq $Comment &&
                $ServiceData{"ValidID"} == $ValidID
            ) {
                $CountUnchanged++;
            } else {
                $CountUpdate++;
                if ($Self->{Verbose}) {
                    $Self->Print("  updating service $Name:");
                    if ($ServiceData{"Comment"} ne $Comment) {
                        $Self->Print("    Comment->" . $Comment);
                    }
                    if ($ServiceData{"ValidID"} != $ValidID) {
                        $Self->Print("    ValidID->" . $ValidID);
                    }
                }
                unless ($Self->_ServiceUpdate(
                    ServiceID => $ServiceID,
                    Name      => $Name,
                    Comment   => $Comment,
                    ValidID   => $ValidID,
                )) {
                    $CountError++;
                    next;
                }
            }
        } else {
            $CountAdd++;
            if ($Self->{Verbose}) {
                $Self->Print("  adding service $Name");
            }
            unless ($Self->_ServiceAdd(
                Name => $Name,
                Comment => $Comment,
                ValidID => $ValidID,
            )) {
                $CountError++;
                next;
            }
        }
    }
}

sub _ServiceUpdate {
    my ( $Self, %Param ) = @_;

    unless ($Self->{DryRun}) {
        my @s = split(/::/, $Param{Name});
        my $NameShort = pop @s;
        my $Parent = join("::", @s);
        my $ParentID;
        if ($Parent) {
            $ParentID = $ServiceObject->ServiceLookup(Name => $Parent);
            unless ($ParentID) {
                $Self->PrintError("Parent Service does not exist: $Parent");
                return 0;
            }
        } else {
            $ParentID = 0;
        }
        $ServiceObject->ServiceUpdate(
            ServiceID => $Param{ServiceID},
            Name      => $NameShort,
            ParentID  => $ParentID,
            Comment   => $Param{Comment},
            ValidID   => $Param{ValidID},
            UserID    => 1,
        );
    }
}

sub _ServiceAdd {
    my ( $Self, %Param ) = @_;

    unless ($Self->{DryRun}) {
        my @s = split(/::/, $Param{Name});
        my $NameShort = pop @s;
        my $Parent = join("::", @s);
        my $ParentID;
        if ($Parent) {
            $ParentID = $ServiceObject->ServiceLookup(Name => $Parent);
            unless ($ParentID) {
                $Self->PrintError("Parent Service does not exist: $Parent");
                return 0;
            }
        } else {
            $ParentID = 0;
        }
        $ServiceObject->ServiceAdd(
            Name      => $NameShort,
            ParentID  => $ParentID,
            Comment   => $Param{Comment},
            ValidID   => $Param{ValidID},
            UserID    => 1,
        );
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
        $Self->Print($Param{InputErrors} . " faulty input lines in file " .
            $Self->{SourcePath});
    }
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->{Data} = $Self->_SlurpCSV();
    $Self->_CheckUnique() or return $Self->ExitCodeError();
    $Self->_StoreData();
    $Self->_PrintStatistics(
        ItemName    => "services",
        Unchanged   => $CountUnchanged,
        Added       => $CountAdd,
        Updated     => $CountUpdate,
        InputErrors => $CountError,
    );
    return $Self->ExitCodeOk();
}
1;
