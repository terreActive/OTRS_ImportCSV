# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::CustomerCompany::ImportCSV;

use strict;
use warnings;

use Text::CSV;
$\ = "\n";

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::CustomerCompany',
);
our $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');
our %ValidStrings = reverse $Kernel::OM->Get('Kernel::System::Valid')->ValidList();

our $CountUnchanged = 0;
our $CountAdd = 0;
our $CountUpdate = 0;
our $CountError = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Import customer companies.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => "Name of the customer_company CSV file.",
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
    my $headers = join(",", "customer_id", "name", "street", "zip", "city",
        "country", "validity");
    open my $file, '<:encoding(UTF-8)', $Self->{SourcePath};
    my $firstLine = <$file>;
    close $file;
    chomp $firstLine;
    if ($firstLine ne $headers) {
        $Self->Print("CSV headers are: " . $firstLine);
        $Self->Print("expected: " . $headers);
        die "File $Self->{SourcePath} has bad CSV header line.\n";
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

sub _StoreData {
    my ( $Self, %Param ) = @_;

    for (@{$Self->{Data}}) {
        my ($CustomerID, $Name, $Street, $ZIP, $City, $Country, $Validity) = @$_;

        my $ValidID = $ValidStrings{$Validity};
        unless ($ValidID) {
            $Self->PrintError("Invalid validity: $Validity");
            $CountError++;
            next;
        }

        my %CustomerCompany = $CustomerCompanyObject->CustomerCompanyGet(
            CustomerID => $CustomerID,
            Silent => 1,
        );

        if ($CustomerCompany{CustomerID}) {
            if (
                ($CustomerCompany{CustomerCompanyName}    // "") eq $Name    &&
                ($CustomerCompany{CustomerCompanyStreet}  // "") eq $Street  &&
                ($CustomerCompany{CustomerCompanyZIP}     // "") eq $ZIP     &&
                ($CustomerCompany{CustomerCompanyCity}    // "") eq $City    &&
                ($CustomerCompany{CustomerCompanyCountry} // "") eq $Country &&
                ($CustomerCompany{ValidID}                // "") eq $ValidID
            ) {
                $CountUnchanged++;
            } else {
                $CountUpdate++;
                if ($Self->{Verbose}) {
                    $Self->Print("  updating company $Name($CustomerID):");
                    if (($CustomerCompany{"CustomerCompanyName"}    // "") ne $Name) {
                        $Self->Print("    Name->" . $Name);
                    }
                    if (($CustomerCompany{"CustomerCompanyStreet"}  // "") ne $Street) {
                        $Self->Print("    Street->" . $Street);
                    }
                    if (($CustomerCompany{"CustomerCompanyZIP"}     // "") ne $ZIP) {
                        $Self->Print("    ZIP->" . $ZIP);
                    }
                    if (($CustomerCompany{"CustomerCompanyCity"}    // "") ne $City) {
                        $Self->Print("    City->" . $City);
                    }
                    if (($CustomerCompany{"CustomerCompanyCountry"} // "") ne $Country) {
                        $Self->Print("    Country->" . $Country);
                    }
                    if (($CustomerCompany{"ValidID"}                // 0) != $ValidID) {
                        $Self->Print("    ValidID->" . $ValidID);
                    }
                }
                unless ($Self->{DryRun}) {
                    $CustomerCompanyObject->CustomerCompanyUpdate(
                        CustomerID             => $CustomerID,
                        CustomerCompanyName    => $Name,
                        CustomerCompanyStreet  => $Street,
                        CustomerCompanyZIP     => $ZIP,
                        CustomerCompanyCity    => $City,
                        CustomerCompanyCountry => $Country,
                        ValidID                => $ValidID,
                        UserID                 => 1,
                    );
                }
            }
        } else {
            $CountAdd++;
            if ($Self->{Verbose}) {
                $Self->Print("  adding company $Name");
            }
            unless ($Self->{DryRun}) {
                $CustomerCompanyObject->CustomerCompanyAdd(
                    CustomerID             => $CustomerID,
                    CustomerCompanyName    => $Name,
                    CustomerCompanyStreet  => $Street,
                    CustomerCompanyZIP     => $ZIP,
                    CustomerCompanyCity    => $City,
                    CustomerCompanyCountry => $Country,
                    ValidID                => $ValidID,
                    UserID                 => 1,
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
        ItemName    => "companies",
        Unchanged   => $CountUnchanged,
        Added       => $CountAdd,
        Updated     => $CountUpdate,
        InputErrors => $CountError,
    );
    return $Self->ExitCodeOk();
}
1;
