# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::CustomerUserCustomer::ImportCSV;

use strict;
use warnings;

use List::Compare;
use Text::CSV;
$\ = "\n";

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::CustomerUser',
);
our $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

our $CountUnchanged = 0;
our $CountAdd = 0;
our $CountRemoved = 0;
our $CountError = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Connect customer users to customers.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => 'Name of the customer_user_customer CSV file.',
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
    my $headers = join(",", "login","customer_id");

    open my $file, '<:encoding(UTF-8)', $Self->{SourcePath};
    my $firstLine = <$file>;
    close $file;
    chomp $firstLine;
    if ($firstLine ne $headers) {
        $Self->Print("CSV headers are: " . $firstLine);
        $Self->Print("expected: " . $headers);
        die "File $Self->{SourcePath} has bad CSV header line.\n";
    }
}

sub _SlurpCSV() {
    my ( $Self, %Param ) = @_;

    my %Data;
    $Self->Print("Reading " . $Self->{SourcePath}) if ($Self->{Verbose});
    open my $file, '<:encoding(UTF-8)', $Self->{SourcePath};
    my $csv = Text::CSV->new;
    <$file>; # skip headers
    while (<$file>) {
        $csv->parse($_);
        my @row = $csv->fields();
        $Data{$row[0]} = [] unless ($Data{$row[0]});
        push @{$Data{$row[0]}}, $row[1];
    }
    close $file;
    return \%Data;
}

sub _StoreData {
    my ( $Self, %Param ) = @_;

    my %CustomerUsers = $CustomerUserObject->CustomerSearch(
        UserLogin => '*',
        Valid  => 0,
        Limit => 999999,
        UserID => 1,
    );
    for my $Login (keys %CustomerUsers) {
        my $shouldCustomerIDs = $Self->{Data}->{$Login};
        unless ($shouldCustomerIDs) {
            $CountError++;
            $Self->PrintError("Customer User $Login company is missing.");
            next;
        }
        my @hasCustomerIDs = $CustomerUserObject->CustomerIDs(User => $Login);
        $CountUnchanged += scalar(@hasCustomerIDs);
        my $lc = List::Compare->new(\@hasCustomerIDs, $shouldCustomerIDs);
        for ($lc->get_unique()) {
            $CountRemoved++;
            $CountUnchanged--;
            if ($Self->{Verbose}) {
                $Self->Print("Removing customer $_ from customer user $Login");
            }
            unless ($Self->{DryRun}) {
                if (!$CustomerUserObject->CustomerUserCustomerMemberAdd(
                    CustomerUserID => $Login,
                    CustomerID     => $_,
                    Active         => 0,
                    UserID         => 1,
                )) {
                    $CountError++;
                    $Self->PrintError("Removing customer $_ from customer user $Login failed");
                }
            }
        }
        for ($lc->get_complement()) {
            $CountAdd++;
            if ($Self->{Verbose}) {
                $Self->Print("Adding customer $_ to customer user $Login");
            }
            unless ($Self->{DryRun}) {
                if (!$CustomerUserObject->CustomerUserCustomerMemberAdd(
                    CustomerUserID => $Login,
                    CustomerID     => $_,
                    Active         => 1,
                    UserID         => 1,
                )) {
                    $CountError++;
                    $Self->PrintError("Adding customer $_ from customer user $Login failed");
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
    $Self->_StoreData();
    $Self->_PrintStatistics(
        ItemName    => "customer user affiliations",
        Unchanged   => $CountUnchanged,
        Added       => $CountAdd,
        Removed     => $CountRemoved,
        InputErrors => $CountError,
    );
    return $Self->ExitCodeOk();
}
1;
