# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2025 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use strict;
use warnings;
use utf8;

# core modules
use MIME::Base64;

# CPAN modules
use Test2::V0;

# OTOBO modules
use Kernel::GenericInterface::Debugger;
use Kernel::GenericInterface::Operation::Session::SessionCreate;
use Kernel::GenericInterface::Operation::Ticket::TicketGet;
use Kernel::System::UnitTest::RegisterDriver;    # Set up $Kernel::OM and $main::Self
use Kernel::System::VariableCheck qw(:all);

our $Self;

my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

# Disable SessionCheckRemoteIP setting.
$ConfigObject->Set(
    Key   => 'SessionCheckRemoteIP',
    Value => 0,
);

# Skip SSL certificate verification.
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        SkipSSLVerify => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# Get a random number.
my $RandomID = $Helper->GetRandomNumber();

# Disable Document Search related event module.
$Helper->ConfigSettingChange(
    Valid => 0,
    Key   => 'DynamicField::EventModulePost###1000-TicketIndexManagement',
    Value => {},
);

# Create a new user for current test.
my $UserLogin = $Helper->TestUserCreate(
    Groups => ['users'],
);
my $Password = $UserLogin;

my $UserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
    UserLogin => $UserLogin,
);

my %SkipFields = (
    Age                       => 1,
    AgeTimeUnix               => 1,
    UntilTime                 => 1,
    SolutionTime              => 1,
    SolutionTimeWorkingTime   => 1,
    EscalationTime            => 1,
    EscalationDestinationIn   => 1,
    EscalationTimeWorkingTime => 1,
    UpdateTime                => 1,
    UpdateTimeWorkingTime     => 1,
    Created                   => 1,
    Changed                   => 1,
    UnlockTimeout             => 1,
);

my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

# Add new dynamic field.
my $AttachmentDynamicFieldID = $DynamicFieldObject->DynamicFieldAdd(
    Name   => 'DynamicFieldAttachment' . $RandomID,
    Config => {
        Name        => 'Config Name',
        Description => 'Description for Dynamic Field.',
    },
    Label      => 'Attachment label',
    FieldOrder => 11000,
    FieldType  => 'Attachment',
    ObjectType => 'Ticket',
    ValidID    => 1,
    UserID     => 1,
);
$Self->True(
    $AttachmentDynamicFieldID,
    'Attachment dynamic field created.'
);

# Get dynamic field config.
my $AttachmentDynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
    ID => $AttachmentDynamicFieldID
);

# Create ticket.
my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

my $TicketID = $TicketObject->TicketCreate(
    Title        => 'Ticket One Title',
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'new',
    CustomerID   => '123465',
    CustomerUser => 'customerOne@example.com',
    OwnerID      => 1,
    UserID       => 1,
);

# Sanity check.
$Self->True(
    $TicketID,
    "TicketCreate() successful for Ticket One ID $TicketID",
);

# Put attachment to the upload cache.
my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');

my $FormID = $UploadCacheObject->FormIDCreate();

my $UploadSuccess = $UploadCacheObject->FormIDAddFile(
    FormID      => $FormID,
    Filename    => 'somefile.txt',
    Content     => 'Attachment content',
    ContentType => 'text/plain',
    Disposition => 'inline',
);

$Self->True(
    $UploadSuccess,
    'Attachment added to the upload cache.'
);

# Create backend object and delegates.
my $BackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
$Self->Is(
    ref $BackendObject,
    'Kernel::System::DynamicField::Backend',
    'Backend object was created successfully',
);

# Set dynamic field.
my $AttachmentDynamicFieldSuccess = $BackendObject->ValueSet(
    DynamicFieldConfig => $AttachmentDynamicFieldConfig,
    ObjectID           => $TicketID,
    Value              => {
        Filename    => 'somefile.txt',
        Content     => 'Attachment content',
        ContentType => 'text/plain',
        Disposition => 'inline',
    },
    UserID => 1,
);
$Self->True(
    $AttachmentDynamicFieldSuccess,
    "Dynamic field 'DynamicFieldAttachemt$RandomID' is set.",
);

# Get the Ticket entry without dynamic fields.
my %TicketEntryOne = $TicketObject->TicketGet(
    TicketID      => $TicketID,
    DynamicFields => 0,
    UserID        => $UserID,
);
$TicketEntryOne{TimeUnit} = $TicketObject->TicketAccountedTimeGet( TicketID => $TicketID );

$Self->True(
    IsHashRefWithData( \%TicketEntryOne ),
    "TicketGet() successful for Local TicketGet One ID $TicketID",
);

for my $Key ( sort keys %TicketEntryOne ) {
    if ( !defined $TicketEntryOne{$Key} ) {
        $TicketEntryOne{$Key} = '';
    }
    if ( $SkipFields{$Key} ) {
        delete $TicketEntryOne{$Key};
    }
}

my $FormatDynamicFields = sub {
    my %Param = @_;

    my %TicketRaw = %{ $Param{Ticket} };
    my %Ticket;
    my @DynamicFields;

    ATTRIBUTE:
    for my $Attribute ( sort keys %TicketRaw ) {

        if ( $Attribute =~ m{\A DynamicField_(.*) \z}msx ) {
            my $DynamicFieldName = $1;

            if ( $DynamicFieldName eq "DynamicFieldAttachment$RandomID" ) {

                # Expected dynamic field value.
                $TicketRaw{$Attribute} = [
                    {
                        "Content"     => "QXR0YWNobWVudCBjb250ZW50\n",
                        "ContentType" => "text/plain",
                        "Filename"    => "somefile.txt",
                        "FilesizeRaw" => 18,
                    },
                ];
            }

            push @DynamicFields, {
                Name  => $DynamicFieldName,
                Value => $TicketRaw{$Attribute},
            };
            next ATTRIBUTE;
        }

        $Ticket{$Attribute} = $TicketRaw{$Attribute};
    }

    # Add dynamic fields array into 'DynamicField' hash key if any.
    if (@DynamicFields) {
        $Ticket{DynamicField} = \@DynamicFields;
    }

    return %Ticket;
};

# Get the Ticket entry with dynamic fields.
my %TicketEntryOneDF = $TicketObject->TicketGet(
    TicketID      => $TicketID,
    DynamicFields => 1,
    UserID        => $UserID,
);
$TicketEntryOneDF{TimeUnit} = $TicketObject->TicketAccountedTimeGet( TicketID => $TicketID );

$Self->True(
    IsHashRefWithData( \%TicketEntryOneDF ),
    "TicketGet() successful with DF for Local TicketGet One ID $TicketID",
);

for my $Key ( sort keys %TicketEntryOneDF ) {
    if ( !defined $TicketEntryOneDF{$Key} ) {
        $TicketEntryOneDF{$Key} = '';
    }
    if ( $SkipFields{$Key} ) {
        delete $TicketEntryOneDF{$Key};
    }
}

%TicketEntryOneDF = $FormatDynamicFields->(
    Ticket => \%TicketEntryOneDF,
);

# Set web-service name.
my $WebserviceName = '-Test-' . $RandomID;

# Create web-service object.
my $WebserviceObject = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');
$Self->Is(
    'Kernel::System::GenericInterface::Webservice',
    ref $WebserviceObject,
    "Create web service object",
);

my $WebserviceID = $WebserviceObject->WebserviceAdd(
    Name   => $WebserviceName,
    Config => {
        Debugger => {
            DebugThreshold => 'debug',
        },
        Provider => {
            Transport => {
                Type => '',
            },
        },
    },
    ValidID => 1,
    UserID  => 1,
);
$Self->True(
    $WebserviceID,
    "Added Web Service",
);

# Fet remote host with some precautions for certain unit test systems.
my $Host = $Helper->GetTestHTTPHostname();

# Prepare web-service config.
my $RemoteSystem =
    $ConfigObject->Get('HttpType')
    . '://'
    . $Host
    . '/'
    . $ConfigObject->Get('ScriptAlias')
    . '/nph-genericinterface.pl/WebserviceID/'
    . $WebserviceID;

$RemoteSystem =~ s{/+nph}{/nph}smxg;

my $WebserviceConfig = {
    Name        => '',
    Description =>
        'Test for Ticket Connector using SOAP transport backend.',
    Debugger => {
        DebugThreshold => 'debug',
        TestMode       => 1,
    },
    Provider => {
        Transport => {
            Type   => 'HTTP::SOAP',
            Config => {
                MaxLength => 10000000,
                NameSpace => 'http://otobo.org/SoapTestInterface/',
                Endpoint  => $RemoteSystem,
            },
        },
        Operation => {
            TicketGet => {
                Type => 'Ticket::TicketGet',
            },
            SessionCreate => {
                Type => 'Session::SessionCreate',
            },
        },
    },
    Requester => {
        Transport => {
            Type   => 'HTTP::SOAP',
            Config => {
                NameSpace => 'http://otobo.org/SoapTestInterface/',
                Encoding  => 'UTF-8',
                Endpoint  => $RemoteSystem,
                Timeout   => 120,
            },
        },
        Invoker => {
            TicketGet => {
                Type => 'Test::TestSimple',
            },
            SessionCreate => {
                Type => 'Test::TestSimple',
            },
        },
    },
};

# Update web-service with real config.
# The update is needed because we are using the WebserviceID for the Endpoint in config.
my $WebserviceUpdate = $WebserviceObject->WebserviceUpdate(
    ID      => $WebserviceID,
    Name    => $WebserviceName,
    Config  => $WebserviceConfig,
    ValidID => 1,
    UserID  => $UserID,
);
$Self->True(
    $WebserviceUpdate,
    "Updated Web Service $WebserviceID - $WebserviceName",
);

# Get SessionID - create requester object.
my $RequesterSessionObject = $Kernel::OM->Get('Kernel::GenericInterface::Requester');
$Self->Is(
    'Kernel::GenericInterface::Requester',
    ref $RequesterSessionObject,
    "SessionID - Create requester object",
);

# Start requester with our web-service.
my $RequesterSessionResult = $RequesterSessionObject->Run(
    WebserviceID => $WebserviceID,
    Invoker      => 'SessionCreate',
    Data         => {
        UserLogin => $UserLogin,
        Password  => $Password,
    },
);

my $NewSessionID = $RequesterSessionResult->{Data}->{SessionID};

my @Tests = (
    {
        Name           => 'Test Ticket 1',
        SuccessRequest => '1',
        RequestData    => {
            TicketID => $TicketID,
        },
        ExpectedReturnRemoteData => {
            Success => 1,
            Data    => {
                Ticket => \%TicketEntryOne,
            },
        },
        ExpectedReturnLocalData => {
            Success => 1,
            Data    => {
                Ticket => [ \%TicketEntryOne, ],
            },
        },
        Operation => 'TicketGet',
    },
    {
        Name           => 'Test Ticket 1 With DF',
        SuccessRequest => '1',
        RequestData    => {
            TicketID      => $TicketID,
            DynamicFields => 1,
        },
        ExpectedReturnRemoteData => {
            Success => 1,
            Data    => {
                Ticket => \%TicketEntryOneDF,
            },
        },
        ExpectedReturnLocalData => {
            Success => 1,
            Data    => {
                Ticket => [ \%TicketEntryOneDF, ],
            },
        },
        Operation => 'TicketGet',
    },
);

my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
    DebuggerConfig => {
        DebugThreshold => 'debug',
        TestMode       => 1,
    },
    WebserviceID      => $WebserviceID,
    CommunicationType => 'Provider',
);
$Self->Is(
    ref $DebuggerObject,
    'Kernel::GenericInterface::Debugger',
    'DebuggerObject instantiate correctly',
);

for my $Test (@Tests) {

    # Create local object.
    my $LocalObject = "Kernel::GenericInterface::Operation::Ticket::$Test->{Operation}"->new(
        DebuggerObject => $DebuggerObject,
        WebserviceID   => $WebserviceID,
    );

    $Self->Is(
        "Kernel::GenericInterface::Operation::Ticket::$Test->{Operation}",
        ref $LocalObject,
        "$Test->{Name} - Create local object",
    );

    my %Auth = (
        UserLogin => $UserLogin,
        Password  => $Password,
    );
    if ( IsHashRefWithData( $Test->{Auth} ) ) {
        %Auth = %{ $Test->{Auth} };
    }

    # Start requester with our web-service.
    my $LocalResult = $LocalObject->Run(
        WebserviceID => $WebserviceID,
        Invoker      => $Test->{Operation},
        Data         => {
            %Auth,
            %{ $Test->{RequestData} },
        },
    );

    # Check result.
    $Self->Is(
        'HASH',
        ref $LocalResult,
        "$Test->{Name} - Local result structure is valid",
    );

    # Create requester object.
    my $RequesterObject = $Kernel::OM->Get('Kernel::GenericInterface::Requester');
    $Self->Is(
        'Kernel::GenericInterface::Requester',
        ref $RequesterObject,
        "$Test->{Name} - Create requester object",
    );

    # Start requester with our web-service.
    my $RequesterResult = $RequesterObject->Run(
        WebserviceID => $WebserviceID,
        Invoker      => $Test->{Operation},
        Data         => {
            %Auth,
            %{ $Test->{RequestData} },
        },
    );

    # Check result.
    $Self->Is(
        'HASH',
        ref $RequesterResult,
        "$Test->{Name} - Requester result structure is valid",
    );

    $Self->Is(
        $RequesterResult->{Success},
        $Test->{SuccessRequest},
        "$Test->{Name} - Requester successful result",
    );

    # Workaround because results from direct call and from SOAP call are a little bit different.
    if ( $Test->{Operation} eq 'TicketGet' ) {

        if ( ref $LocalResult->{Data}->{Ticket} eq 'ARRAY' ) {
            for my $Item ( @{ $LocalResult->{Data}->{Ticket} } ) {
                for my $Key ( sort keys %{$Item} ) {
                    if ( !defined $Item->{$Key} ) {
                        $Item->{$Key} = '';
                    }
                    if ( $SkipFields{$Key} ) {
                        delete $Item->{$Key};
                    }
                    if ( $Key eq 'DynamicField' ) {
                        for my $DF ( @{ $Item->{$Key} } ) {
                            if ( !defined $DF->{Value} ) {
                                $DF->{Value} = '';
                            }
                        }
                    }
                }
            }
        }

        if (
            defined $RequesterResult->{Data}
            && defined $RequesterResult->{Data}->{Ticket}
            )
        {
            if ( ref $RequesterResult->{Data}->{Ticket} eq 'ARRAY' ) {
                for my $Item ( @{ $RequesterResult->{Data}->{Ticket} } ) {
                    for my $Key ( sort keys %{$Item} ) {
                        if ( !defined $Item->{$Key} ) {
                            $Item->{$Key} = '';
                        }
                        if ( $SkipFields{$Key} ) {
                            delete $Item->{$Key};
                        }
                        if ( $Key eq 'DynamicField' ) {
                            for my $DF ( @{ $Item->{$Key} } ) {
                                if ( !defined $DF->{Value} ) {
                                    $DF->{Value} = '';
                                }
                            }
                        }
                    }
                }
            }
            elsif ( ref $RequesterResult->{Data}->{Ticket} eq 'HASH' ) {
                for my $Key ( sort keys %{ $RequesterResult->{Data}->{Ticket} } ) {
                    if ( !defined $RequesterResult->{Data}->{Ticket}->{$Key} ) {
                        $RequesterResult->{Data}->{Ticket}->{$Key} = '';
                    }
                    if ( $SkipFields{$Key} ) {
                        delete $RequesterResult->{Data}->{Ticket}->{$Key};
                    }
                    if ( $Key eq 'DynamicField' ) {
                        for my $DF ( @{ $RequesterResult->{Data}->{Ticket}->{$Key} } ) {
                            if ( !defined $DF->{Value} ) {
                                $DF->{Value} = '';
                            }
                            elsif (
                                ref $DF->{Value} eq 'HASH'
                                && $DF->{Value}->{Filename}
                                && $DF->{Value}->{Filename} eq 'somefile.txt'
                                )
                            {
                                # Workaround, set response in proper format.
                                $DF->{Value} = [
                                    $DF->{Value},
                                ];
                            }
                        }
                    }
                }
            }
        }
    }

    # Remove ErrorMessage parameter from direct call result to be consistent with SOAP call result.
    if ( $LocalResult->{ErrorMessage} ) {
        delete $LocalResult->{ErrorMessage};
    }

    $Self->IsDeeply(
        $RequesterResult,
        $Test->{ExpectedReturnRemoteData},
        "$Test->{Name} - Requester success status (needs configured and running web server)",
    );

    if ( $Test->{ExpectedReturnLocalData} ) {
        $Self->IsDeeply(
            $LocalResult,
            $Test->{ExpectedReturnLocalData},
            "$Test->{Name} - Local result matched with expected local call result.",
        );
    }
    else {
        $Self->IsDeeply(
            $LocalResult,
            $Test->{ExpectedReturnRemoteData},
            "$Test->{Name} - Local result matched with remote result.",
        );
    }

    if ( $Test->{RequestData}->{DynamicFields} ) {
        my ($DynamicFieldData) = grep { $_->{Name} eq 'DynamicFieldAttachment' . $RandomID }
            @{ $RequesterResult->{Data}->{Ticket}->{DynamicField} };

        $Self->Is(
            $DynamicFieldData->{Value}->[0]->{Content},
            "QXR0YWNobWVudCBjb250ZW50\n",
            'Make sure that DynamicField (attachment) has content.'
        );
    }
}

# Cleanup data.

# Delete web service.
my $WebserviceDelete = $WebserviceObject->WebserviceDelete(
    ID     => $WebserviceID,
    UserID => $UserID,
);
$Self->True(
    $WebserviceDelete,
    "Deleted Web Service $WebserviceID",
);

# Delete ticket.
my $TicketDelete = $TicketObject->TicketDelete(
    TicketID => $TicketID,
    UserID   => $UserID,
);

# Sanity check.
$Self->True(
    $TicketDelete,
    "TicketDelete() successful for Ticket ID $TicketID",
);

# Delete the dynamic field.
my $DFDelete = $DynamicFieldObject->DynamicFieldDelete(
    ID      => $AttachmentDynamicFieldID,
    UserID  => 1,
    Reorder => 0,
);

# Sanity check.
$Self->True(
    $DFDelete,
    "DynamicFieldDelete() successful for Field ID $AttachmentDynamicFieldID",
);

# Cleanup cache.
$Kernel::OM->Get('Kernel::System::Cache')->CleanUp();

$Self->DoneTesting();
