# --
# Copyright (C) 2021 Othmar Wigger, <othmar.wigger@terreactive.ch>
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Console::Command::Admin::CustomerGroup::ImportCSV;

use strict;
use warnings;

use Text::CSV;
$\ = "\n";

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::CustomerGroup',
    'Kernel::System::CustomerCompany'
);
our $CustomerGroupObject = $Kernel::OM->Get('Kernel::System::CustomerGroup');
our %CustomerCompanyList = $Kernel::OM->Get('Kernel::System::CustomerCompany')
    ->CustomerCompanyList(Limit => 0);
our $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
our %GroupFullnames;
our %GroupShortnames;

our $CountUnchanged = 0;
our $CountAdd = 0;
our $CountRemoved = 0;
our $CountError = 0;

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Import customer companies from CSV file.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => 'Name of the customer_company CSV file.',
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
    my $headers = join(",", "customer_id", "group", "validity");
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

sub _StoreData {
    my ( $Self, %Param ) = @_;

    for (@{$Self->{Data}}) {
        my ($CustomerID, $Group, $Validity) = @$_;

        unless ($CustomerCompanyList{$CustomerID}) {
            $Self->PrintError("Invalid customer company $CustomerID");
            $CountError++;
            next;
        }

        my $GroupID = $Self->_GroupLookupByShortname(Group => $Group);
        unless ($GroupID) {
            $Self->PrintError("Invalid groupname $Group");
            $CountError++;
            next;
        }

        if ($Validity ne 'valid' && $Validity ne 'invalid') {
            $Self->PrintError("Invalid validity: $Validity");
            $CountError++;
            next;
        }

        my %GroupIDs = $CustomerGroupObject->GroupCustomerList(
            CustomerID => $CustomerID,
            Type => 'rw',
            Context => 'Ticket::CustomerID::Same',
            Result => 'HASH',
        );
        if ($GroupIDs{$GroupID} xor ($Validity eq 'valid')) {
            if ($Validity eq 'valid') {
                $CountAdd++;
                if ($Self->{Verbose}) {
                    $Self->Print("  adding group $Group to customer company $CustomerID");
                }
            } else {
                $CountRemoved++;
                if ($Self->{Verbose}) {
                    $Self->Print("  removing group $Group from customer company $CustomerID");
                }
            }
            unless ($Self->{DryRun}) {
                $CustomerGroupObject->GroupCustomerAdd(
                    GID => $GroupID,
                    CustomerID => $CustomerID,
                    Permission => {
                        'Ticket::CustomerID::Same' => { rw => $Validity eq 'valid' ? 1 : 0 }
                    },
                    UserID => 1
                )
            }
        } else {
            $CountUnchanged++;
        }
    }
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

sub _GroupLookupByShortname { my ( $Self, %Param ) = @_;

    my $Group = $Param{Group};
    die ("Need Group") unless ($Group);

    my $GroupID = $GroupFullnames{$Group};
    return $GroupID if ($GroupID);

    $GroupID = $GroupShortnames{$Group};
    return $GroupID if ($GroupID);
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

    $Self->_InitializeGroupLists();
    $Self->{Data} = $Self->_SlurpCSV();
    $Self->_StoreData();
    $Self->_PrintStatistics(
        ItemName    => "groups",
        Unchanged   => $CountUnchanged,
        Added       => $CountAdd,
        Removed     => $CountRemoved,
        InputErrors => $CountError,
    );
    return $Self->ExitCodeOk();
}
1;
