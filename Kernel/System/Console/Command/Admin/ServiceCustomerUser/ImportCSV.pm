# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::ServiceCustomerUser::ImportCSV;

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
our $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');

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
    my $headers = join(",", "login", "service", "validity");

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

    my %Add; my %Remove;
    $Self->Print("Reading " . $Self->{SourcePath}) if ($Self->{Verbose});
    open my $file, '<:encoding(UTF-8)', $Self->{SourcePath};
    my $csv = Text::CSV->new;
    <$file>; # skip headers
    while (<$file>) {
        $csv->parse($_);
        my @row = $csv->fields();
        if ( $row[2] eq "valid" ) {
            $Add{$row[1]} = [] unless ($Add{$row[1]});
            push @{$Add{$row[1]}}, $row[0];
        } elsif ( $row[2] eq "invalid" ) {
            $Remove{$row[1]} = [] unless ($Remove{$row[1]});
            push @{$Remove{$row[1]}}, $row[0];
        } else {
            $Self->PrintError("Invalid validity: $row[2]");
            $CountError++;
        }
    }
    close $file;
    return ( \%Add, \%Remove );
}

sub _StoreData {
    my ( $Self, %Param ) = @_;

    # validate customer users
    my %CustomerUsers = $CustomerUserObject->CustomerSearch(
        UserLogin => '*',
        Valid  => 0,
        Limit => 999999,
        UserID => 1,
    );

    # go through services found in CSV
    my @AddServices = keys %{$Self->{Add}};
    my @RemoveServices = keys %{$Self->{Remove}};
    my $ListObject = List::Compare->new('--unsorted', \@AddServices, \@RemoveServices);
    my @Services = $ListObject->get_union;

    for my $Service (@Services) {
        my $ServiceID = $ServiceObject->ServiceLookup( Name => $Service );
        unless ($ServiceID) {
            $Self->PrintError("Invalid service: $Service");
            $CountError++;
            next;
        }
        my @CustomerUsersIs = $ServiceObject->CustomerUserServiceMemberList(
            ServiceID => $ServiceID,
            DefaultServices => 1,
            Result => "ID",
        );

        # remove customer users from service
        my $CustomerUsersRemove = $Self->{Remove}->{$Service};
        $ListObject = List::Compare->new(
            \@CustomerUsersIs,
            $CustomerUsersRemove
        );
        for ($ListObject->get_intersection()) {
            $CountRemoved++;
            if ($Self->{Verbose}) {
                $Self->Print("Removing customer user $_ from service $Service");
            } 
            unless ($Self->{DryRun}) {
                $ServiceObject->CustomerUserServiceMemberAdd(
                    CustomerUserLogin => $_,
                    ServiceID         => $ServiceID,
                    Active            => 0,
                    UserID            => 1,
                );
            }
        }

        # add customer users to service
        my $CustomerUsersAdd = $Self->{Add}->{$Service};
        $ListObject = List::Compare->new(
            \@CustomerUsersIs,
            $CustomerUsersAdd
        );
        for ($ListObject->get_complement()) {
            $CountAdd++;
            if ($Self->{Verbose}) {
                $Self->Print("Adding customer user $_ to service $Service");
            } 
            unless ($Self->{DryRun}) {
                $ServiceObject->CustomerUserServiceMemberAdd(
                    CustomerUserLogin => $_,
                    ServiceID         => $ServiceID,
                    Active            => 1,
                    UserID            => 1,
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
        $Self->Print($Param{InputErrors} . " errors in " . $Self->{SourcePath});
    }
}

sub Run {
    my ( $Self, %Param ) = @_;

    ($Self->{Add}, $Self->{Remove}) = $Self->_SlurpCSV();
    $Self->_StoreData();
    $Self->_PrintStatistics(
        ItemName    => "customer user affiliations",
        Added       => $CountAdd,
        Removed     => $CountRemoved,
        InputErrors => $CountError,
    );
    return $Self->ExitCodeOk();
}
1;
