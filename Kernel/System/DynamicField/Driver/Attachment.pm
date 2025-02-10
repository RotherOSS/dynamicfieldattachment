# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2022 Rother OSS GmbH, https://otobo.de/
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

package Kernel::System::DynamicField::Driver::Attachment;

## nofilter(TidyAll::Plugin::OTOBO::Perl::ParamObject)

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::DB',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::VirtualFS',
    'Kernel::System::Web::UploadCache',
    'Kernel::System::Web::Request',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Ticket',
    'Kernel::System::Ticket::Article',
    'Kernel::System::YAML',
);

use Kernel::Language qw(Translatable);
use Kernel::System::VariableCheck qw(:all);

use MIME::Base64 qw();

use parent qw(Kernel::System::DynamicField::Driver::BaseText);

=head1 NAME

Kernel::System::DynamicField::Driver::Attachment

=head1 SYNOPSIS

DynamicFields Attachment Driver delegate

=head1 PUBLIC INTERFACE

This module implements the public interface of L<Kernel::System::DynamicField::Backend>.
Please look there for a detailed reference of the functions.

=over 4

=item new()

usually, you want to create an instance of this
by using Kernel::System::DynamicField::Backend->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # set field behaviors
    $Self->{Behaviors} = {
        'IsACLReducible'               => 0,
        'IsNotificationEventCondition' => 1,
        'IsSortable'                   => 0,
        'IsFiltrable'                  => 0,
        'IsStatsCondition'             => 0,
        'IsCustomerInterfaceCapable'   => 1,
        'IsAttachement'                => 1,
    };

    # get the Dynamic Field Backend custom extensions
    my $DynamicFieldDriverExtensions
        = $Kernel::OM->Get('Kernel::Config')->Get('DynamicFields::Extension::Driver::Text');

    EXTENSION:
    for my $ExtensionKey ( sort keys %{$DynamicFieldDriverExtensions} ) {

        # skip invalid extensions
        next EXTENSION if !IsHashRefWithData( $DynamicFieldDriverExtensions->{$ExtensionKey} );

        # create a extension config shortcut
        my $Extension = $DynamicFieldDriverExtensions->{$ExtensionKey};

        # check if extension has a new module
        if ( $Extension->{Module} ) {

            # check if module can be loaded
            if ( !$Kernel::OM->Get('Kernel::System::Main')->RequireBaseClass( $Extension->{Module} ) ) {
                die "Can't load dynamic fields backend module"
                    . " $Extension->{Module}! $@";
            }
        }

        # check if extension contains more behaviors
        if ( IsHashRefWithData( $Extension->{Behaviors} ) ) {

            %{ $Self->{Behaviors} } = (
                %{ $Self->{Behaviors} },
                %{ $Extension->{Behaviors} }
            );
        }
    }

    return $Self;
}

=item ValueGet()

returns a hash holding the file as well as it's info

    my $Attachment = $DynamicFieldDriver->ValueGet(
        DynamicFieldConfig     => \%DynamicFieldConfig,
        ObjectID               => $ObjectID,            # TicketID or ArticleID
        Download               => 0,                    # or 1, optional, returns file + info if 1
        Filename               => 'StarryNight.jpg',    # Required if Download == 1
    );

=cut

sub ValueGet {
    my ( $Self, %Param ) = @_;
    my $Download = $Param{Download} || 0;

    for my $Needed (qw(DynamicFieldConfig ObjectID)) {
        if ( !$Param{$Needed} ) {

            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Got no $Needed in DynamicField Driver Attachment ValueGet!",
            );

            return;
        }

    }

    my $DFValue = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->ValueGet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
    );

    return if !$DFValue;
    return if !IsArrayRefWithData($DFValue);
    return if !IsHashRefWithData( $DFValue->[0] );

    my $YAMLObject = $Kernel::OM->Get('Kernel::System::YAML');

    # extract real values
    my @ReturnData;
    for my $Item ( @{$DFValue} ) {

        push @ReturnData, $YAMLObject->Load(
            Data => $Item->{ValueText},
        ) || {};
    }

    if ( !$Download ) {
        return \@ReturnData;
    }

    for my $Needed (qw(Filename)) {
        if ( !$Param{$Needed} ) {

            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Got no $Needed in DynamicField Driver Attachment ValueGet!",
            );
            return;
        }
    }
    my @FileFound = grep { $Param{Filename} eq $_->{Filename} } @ReturnData;

    my $StorageLocation = 'DynamicField/' . $Param{DynamicFieldConfig}->{ID} . '/'
        . $Param{DynamicFieldConfig}->{ObjectType} . '/'
        . $Param{ObjectID} . '/' . $Param{Filename};

        # Check if we found the file we have to download, and if that record has a StorageLocation
    if (
        !@FileFound
        || !IsHashRefWithData( $FileFound[0] )
        || !length $FileFound[0]->{StorageLocation}
        || $StorageLocation ne $FileFound[0]->{StorageLocation}
        )
    {

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  =>
                'Could not validate $Param{Filename} in DynamicFieldAttachment ValueGetDownload!',
        );

        return;
    }

    # get virtualfs object
    my $VirtualFSObject = $Kernel::OM->Get('Kernel::System::VirtualFS');

    # find all attachments of this change
    my @Attachments = $VirtualFSObject->Find(
        Filename    => $FileFound[0]->{StorageLocation},
        Preferences => {
            ObjectID => $Param{ObjectID},
        },
    );

    # return error if file does not exist
    if ( !@Attachments ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Message  => "No such attachment ($FileFound[0]->{StorageLocation})!",
            Priority => 'error',
        );
        return;
    }

    # get data for attachment
    my %AttachmentData = $VirtualFSObject->Read(
        Filename => $FileFound[0]->{StorageLocation},
        Mode     => 'binary',
    );

    my $AttachmentInfo = {
        %AttachmentData,
        Filename    => $FileFound[0]->{Filename},
        Content     => ${ $AttachmentData{Content} },
        ContentType => $AttachmentData{Preferences}->{ContentType},
        Type        => 'attachment',
        Filesize    => $AttachmentData{Preferences}->{FilesizeRaw},
        ObjectID    => $Param{ObjectID},
    };

    return $AttachmentInfo;
}

sub ValueSet {
    my ( $Self, %Param ) = @_;

    if ( IsArrayRefWithData( $Param{Value} ) ) {

        return 1 if !defined $Param{Value}->[0];

        $Param{Value} = $Param{Value}->[0];
    }

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # For storing our values we need a unique directory structure
    # so we're fetching the FieldID (unique)
    my $FieldID = $Param{DynamicFieldConfig}->{ID};

    # as well as the ObjectType (Article or Ticket)
    # which will be used in the directory path
    my $ObjectType = $Param{DynamicFieldConfig}->{ObjectType};

    # get virtualfs object
    my $VirtualFSObject = $Kernel::OM->Get('Kernel::System::VirtualFS');

    # At first let's see if we have already stored values in the Filesystem & Database
    my $ExistingValues = $Self->ValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ObjectID           => $Param{ObjectID},
    ) || [];

    my @ValueText;

    my $YAMLObject = $Kernel::OM->Get('Kernel::System::YAML');

    # Keep old stored files
    if ( @{$ExistingValues} ) {

        for my $Item ( @{$ExistingValues} ) {
            push @ValueText, {
                ValueText => $YAMLObject->Dump(
                    Data => $Item,
                ),
            };
        }
    }

    # then we'll need the UploadFieldUID which was stored in $Self
    # by EditFieldValueGet or EditFieldValueValidate and under which, used as FormID
    # the files were stored via the UploadCacheObject

    # get uploadcache object
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
    my $UploadFieldUID    = $Self->{ 'UploadCacheFormID' . $FieldName };
    my $FormID;

    if ( !$UploadFieldUID && $Param{Value} && $Param{Value}->{FormID} ) {
        $FormID = $Param{Value}->{FormID};
    }
    elsif ( !$UploadFieldUID && $Param{Value} && !$Param{Value}->{FormID} ) {
        $FormID = $UploadCacheObject->FormIDCreate();

        for my $Attachment ( $Param{Value} ) {
            if ( $Attachment->{Filename} && $Attachment->{Content} && $Attachment->{ContentType} ) {
                my $Success = $UploadCacheObject->FormIDAddFile(
                    FormID      => $FormID,
                    Filename    => $Attachment->{Filename},
                    Content     => MIME::Base64::decode_base64( $Attachment->{Content} ),
                    ContentType => $Attachment->{ContentType},
                    Disposition => 'attachment',
                );
                return if !$Success;
            }
        }
    }

    return if !$UploadFieldUID && !$FormID;

    my @Attachments = $UploadCacheObject->FormIDGetAllFilesData(
        FormID => $UploadFieldUID // $FormID,
    );

    for my $Item (@Attachments) {

        # Now we'll try to store the cached object
        # ObjectID = TicketID or ArticleID
        # ObjectType = Ticket or Article
        my $Success = $VirtualFSObject->Write(
            Filename    => "DynamicField/$FieldID/$ObjectType/$Param{ObjectID}/$Item->{Filename}",
            Mode        => 'binary',
            Content     => \$Item->{Content},
            Preferences => {
                ContentID   => $Item->{ContentID} || '',
                ContentType => $Item->{ContentType},
                ObjectID    => $Param{ObjectID},
                ObjectType  => $ObjectType,
                UserID      => $Param{UserID},
            },
        );

        if ( !$Success ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Cannot add attachment for $ObjectType $Param{ObjectID}",
            );

            return;
        }
        push @ValueText, {
            ValueText => $YAMLObject->Dump(
                Data => {
                    Filename        => $Item->{Filename},
                    StorageLocation => "DynamicField/$FieldID/$ObjectType/$Param{ObjectID}/$Item->{Filename}",
                    Filesize        => $Item->{Filesize},
                    ContentType     => $Item->{ContentType},
                },
            ),
        };
    }

    # if all files are stored correctly we'll remove the cached ones
    $UploadCacheObject->FormIDRemove(
        FormID => $UploadFieldUID // $FormID,
    );

    my $Success;

    # get dynamicfieldvalue object
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    # if all values got deleted we have to call ValueDelete
    # because ValueSet is unable to work on no existing values
    if ( !@ValueText ) {
        $Success = $DynamicFieldValueObject->ValueDelete(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            UserID   => $Param{UserID},
        );

    }
    else {

        $Success = $DynamicFieldValueObject->ValueSet(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            Value    => \@ValueText,
            UserID   => $Param{UserID},
        );

    }

    return $Success;
}

sub ValueDelete {
    my ( $Self, %Param ) = @_;

    my $Values = $Self->ValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ObjectID           => $Param{ObjectID},
        UserID             => $Param{UserID},
    );

    # get virtualfs object
    my $VirtualFSObject = $Kernel::OM->Get('Kernel::System::VirtualFS');

    if ( IsArrayRefWithData($Values) ) {
        for my $Item ( @{$Values} ) {
            my $Success = $VirtualFSObject->Delete(
                Filename => $Item->{StorageLocation},
            );
            if ( !$Success ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  =>
                        "Cannot delete attachments from $Param{DynamicFieldConfig}->{ObjectType} $Param{ObjectID}",
                );

                return;
            }
        }
    }

    my $Success = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->ValueDelete(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
        UserID   => $Param{UserID},
    );

    return $Success;
}

sub SingleValueDelete {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(DynamicFieldConfig FileID ObjectID FieldID)) {
        if ( !$Param{$Needed} ) {

            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Got no $Needed in DynamicField Driver Attachment SingleValueDelete!",
            );

            return;
        }

    }

    my $Values = $Self->ValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ObjectID           => $Param{ObjectID},
    );

    my @ValueText;

    # get virtualfs object
    my $VirtualFSObject = $Kernel::OM->Get('Kernel::System::VirtualFS');

    if ( IsArrayRefWithData($Values) ) {

        my $YAMLObject = $Kernel::OM->Get('Kernel::System::YAML');

        my $Index = 1;
        ATTACHMENT:
        for my $Item ( @{$Values} ) {

            if ( $Param{FileID} eq $Index ) {
                my $Success = $VirtualFSObject->Delete(
                    Filename => $Item->{StorageLocation},
                );
                if ( !$Success ) {
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message  =>
                            "Cannot delete attachments from $Param{DynamicFieldConfig}->{ObjectType} $Param{ObjectID}",
                    );

                    return;
                }
            }
            else {
                push @ValueText, {
                    ValueText => $YAMLObject->Dump(
                        Data => {
                            Filename        => $Item->{Filename},
                            StorageLocation => $Item->{StorageLocation},
                            Filesize        => $Item->{Filesize},
                            ContentType     => $Item->{ContentType},
                        },
                    ),
                };
            }

            $Index++;
        }
    }

    # get dynamicfieldvalue object
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    # if all values got deleted we have to call ValueDelete
    # because ValueSet is unable to work on no existing values
    if ( !@ValueText ) {
        my $Success = $DynamicFieldValueObject->ValueDelete(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            UserID   => $Param{UserID},
        );
        if ( !$Success ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  =>
                    "Cannot delete attachments from $Param{DynamicFieldConfig}->{ObjectType} $Param{ObjectID}",
            );

            return;
        }
    }
    else {
        my $Success = $DynamicFieldValueObject->ValueSet(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            Value    => \@ValueText,
            UserID   => $Param{UserID},
        );
        if ( !$Success ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  =>
                    "Cannot update attachments from $Param{DynamicFieldConfig}->{ObjectType} $Param{ObjectID}",
            );

            return;
        }

    }

    return \@ValueText;
}

sub AllValuesDelete {
    my ( $Self, %Param ) = @_;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    return if !$DBObject->Prepare(
        SQL => '
            SELECT id, value_text, value_date, value_int
            FROM dynamic_field_value
            WHERE field_id = ?
            ORDER BY id
        ',
        Bind => [ \$Param{DynamicFieldConfig}->{ID} ],
    );
    my @Filenames;

    my $YAMLObject = $Kernel::OM->Get('Kernel::System::YAML');

    while ( my @Data = $DBObject->FetchrowArray() ) {
        if ( length $Data[1] ) {
            my $FileInfo = $YAMLObject->Load(
                Data => $Data[1],
            );
            if ( IsHashRefWithData($FileInfo) && length $FileInfo->{StorageLocation} ) {
                push @Filenames, $FileInfo->{StorageLocation};
            }
        }
    }

    # get virtualfs object
    my $VirtualFSObject = $Kernel::OM->Get('Kernel::System::VirtualFS');

    for my $Filename (@Filenames) {
        my $Success = $VirtualFSObject->Delete(
            Filename => $Filename,
        );
        if ( !$Success ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                'Priority' => 'error',
                'Message'  => "Could not delete $Filename",
            );
            return $Success;
        }
    }

    my $Success = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->AllValuesDelete(
        FieldID => $Param{DynamicFieldConfig}->{ID},
        UserID  => $Param{UserID},
    );

    return $Success;
}

sub ValueValidate {
    my ( $Self, %Param ) = @_;

    # check value
    my @Values;
    if ( IsArrayRefWithData( $Param{Value} ) ) {
        @Values = @{ $Param{Value} };
    }
    else {
        @Values = ( $Param{Value} );
    }

    # get dynamicfieldvalue object
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    my $Success;
    for my $Item (@Values) {

        $Success = $DynamicFieldValueObject->ValueValidate(
            Value => {
                ValueText => $Item,
            },
            UserID => $Param{UserID}
        );
        return if !$Success;
    }
    return $Success;
}

sub SearchSQLGet {
    my ( $Self, %Param ) = @_;

    my %Operators = (
        Equals            => '=',
        GreaterThan       => '>',
        GreaterThanEquals => '>=',
        SmallerThan       => '<',
        SmallerThanEquals => '<=',
    );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    if ( $Operators{ $Param{Operator} } ) {
        my $SQL = " $Param{TableAlias}.value_text $Operators{$Param{Operator}} '";
        $SQL .= $DBObject->Quote( $Param{SearchTerm} ) . "' ";
        return $SQL;
    }

    if ( $Param{Operator} eq 'Like' ) {

        my $SQL = $DBObject->QueryCondition(
            Key   => "$Param{TableAlias}.value_text",
            Value => $Param{SearchTerm},
        );

        return $SQL;
    }

    $Kernel::OM->Get('Kernel::System::Log')->Log(
        'Priority' => 'error',
        'Message'  => "Unsupported Operator $Param{Operator}",
    );

    return;
}

sub SearchSQLOrderFieldGet {
    my ( $Self, %Param ) = @_;

    return "$Param{TableAlias}.value_text";
}

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # take config from field config
    my $FieldConfig         = $Param{DynamicFieldConfig}->{Config};
    my $FieldName           = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel          = $Param{DynamicFieldConfig}->{Label};
    my $UploadFileAttribute = ${FieldName} . 'UID';
    my $UploadFieldUID      = $Param{ParamObject}->GetParam( Param => $UploadFileAttribute );

    # Flag if we are dealing with an erroneous submit or a new edit request
    my $NewForm = 0;

    # create form id
    if ( !$UploadFieldUID ) {
        $UploadFieldUID = $Kernel::OM->Get('Kernel::System::Web::UploadCache')->FormIDCreate();
        $NewForm        = 1;
    }

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }

    my $OldStoredAttachments;

    my $ObjectID = $Param{ParamObject}->GetParam( Param => $Param{DynamicFieldConfig}->{ObjectType} . 'ID' );
    if ($ObjectID) {
        $OldStoredAttachments = $Self->ValueGet(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $ObjectID,
            %Param,
        );
    }

    my $NumberOfFiles   = $FieldConfig->{NumberOfFiles}   || 16;
    my $MaximumFileSize = $FieldConfig->{MaximumFileSize} || 20;
    $MaximumFileSize = ( $MaximumFileSize * 1024 * 1024 );
    my $ServerErrorHTML = '';
    my $IsMandatory     = $Param{Mandatory} || '0';

    # Rother OSS / ToDo: Need to redesign DynamicFields, we don´t like to use ParamObject in Kernel/System
    my $ParamObject     = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $InterfaceAction = $ParamObject->{Query}->{param}->{Action}[0];
    my $BaseTemplate;

    if ( $InterfaceAction && $InterfaceAction =~ /^Customer/ ) {

        $BaseTemplate = <<"EOF";
                    <div class="Field DFAttachments">
                        <div class="DnDUploadBox">
[% INCLUDE "FormElements/CustomerAttachmentList.tt" FieldID="$FieldName" FieldName="$FieldName" MaxFiles="$NumberOfFiles" MaxSizePerFile="$MaximumFileSize" Mandatory="$IsMandatory" FormID="$UploadFieldUID"%]
                        </div>
                    </div>
EOF

    }
    else {

        $BaseTemplate = <<"EOF";
[% INCLUDE "FormElements/AttachmentList.tt" FieldID="$FieldName" FieldName="$FieldName" MaxFiles="$NumberOfFiles" MaxSizePerFile="$MaximumFileSize" Mandatory="$IsMandatory" FormID="$UploadFieldUID"%]
EOF

    }

    # EO Rother OSS ToDo

    my $VirtualFSObject = $Kernel::OM->Get('Kernel::System::VirtualFS');
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
    my $Index = 1;
    for my $Item (@Values) {
        $Item->{FileID}       = $Index++;
        $Item->{ObjectID}     = $ObjectID;
        $Item->{FieldID}      = $Param{DynamicFieldConfig}->{ID};
        $Item->{DeleteAction} = 'AjaxDynamicFieldAttachment';

        # get attachment content and add it to UploadCache
        # get data for attachment
        my %AttachmentData = $VirtualFSObject->Read(
            Filename => $Item->{StorageLocation},
            Mode     => 'binary',
        );

        if (%AttachmentData) {
            my $Success = $UploadCacheObject->FormIDAddFile(
                $AttachmentData{Preferences}->%*,
                FormID      => $UploadFieldUID,
                Filename    => $Item->{Filename},
                Content     => $AttachmentData{Content}->$*,
                ContentID   => $Item->{ContentID},
                ContentType => $Item->{ContentType},
                Disposition => 'attachment',
            );
            return if !$Success;
        }
    }

    my $HTMLString = $LayoutObject->Output(
        Template => $BaseTemplate,
        Data     => {
            AttachmentList => \@Values,
        },
    );

    $HTMLString
        .= '<input type="hidden" id="'
        . $UploadFileAttribute
        . '" name="'
        . $UploadFileAttribute
        . '" value="'
        . $UploadFieldUID . '" />';

    # call EditLabelRender on the base driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        Mandatory          => $IsMandatory,
        FieldName          => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub EditFieldValueGet {
    my ( $Self, %Param ) = @_;

    # if we don't have a ParamObject
    # we were called not by a FormSubmit
    # so there are no Params to get and return
    #
    # this is the case for GenericAgent.pm
    # which can fill DynamicFields with template values
    #
    # As long as we can't provide files in Templates
    # that should get stored in here
    # we can return undef
    if ( !$Param{ParamObject} ) {
        return;
    }

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # We store processed uploaded files meta data on the object
    # in order to reduce mysql requests
    if ( IsArrayRefWithData( $Self->{ 'UploadCacheFilesMeta' . $FieldName } ) ) {
        return $Self->{ 'UploadCacheFilesMeta' . $FieldName };
    }

    # just to make sure that we don't end in an infinite loop default it to 16
    my $NumberOfFiles = $Param{DynamicFieldConfig}->{NumberOfFiles} || 16;

    my $MaximumFileSize = $Param{DynamicFieldConfig}->{MaximumFileSize} || 20;

    my $UploadFieldUID = $Param{ParamObject}->GetParam( Param => "${FieldName}UID" );

    # if we didn't have a UID we haven't been called by a submit
    # this shouldn't happen
    my $ObjectID = $Param{ParamObject}->GetParam( Param => $Param{DynamicFieldConfig}->{ObjectType} . 'ID' );
    if ( !$UploadFieldUID ) {
        if ($ObjectID) {
            return $Self->ValueGet(
                FieldID  => $Param{DynamicFieldConfig}->{ID},
                ObjectID => $ObjectID,
                %Param,
            );
        }
        else {
            return [];
        }
    }

    my $Value;
    my @StoredAttachments;

    my $OldStoredAttachments;
    if ($ObjectID) {
        $OldStoredAttachments = $Self->ValueGet(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $ObjectID,
            %Param,
        );
    }

    # if we are dealing with a value we had in the database from an earlier submit/change
    for ( my $i = 0; $i < $NumberOfFiles; $i++ ) {

        # the submitted value looks like 0StoredMyFile.pdf
        # where 0 is the index of the stored values and all after "Stored" is the Filename
        # we need this to delete gui-deleted files from storage
        # filename necessary to have enough info for displaying the entry on an erroneous submit
        # and ServerError Displaying
        my $FileID = $Param{ParamObject}->GetParam( Param => $FieldName . $i );

        if (
            $FileID
            && $FileID =~ /^(\d+)Stored(.*)/
            && IsArrayRefWithData($OldStoredAttachments)
            && IsHashRefWithData( $OldStoredAttachments->[$1] )
            )
        {
            push @StoredAttachments, {
                FileID      => $1,
                Filename    => $2,
                Filesize    => $OldStoredAttachments->[$1]{Filesize},
                ContentType => $OldStoredAttachments->[$1]{ContentType},
                StoredValue => 1,
            };
        }
    }

    # get uploadcache object
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');

    # Get old stored UploadCache files Metainfo
    my @Attachments = $UploadCacheObject->FormIDGetAllFilesMeta(
        FormID => $UploadFieldUID,
    );

    # now let's bring together the info about the old stored attachments as well as the uploaded ones
    if ($OldStoredAttachments) {
        @Attachments = ( @{$OldStoredAttachments}, @Attachments );
    }

    $Self->{ 'UploadCacheFilesMeta' . $FieldName } = \@Attachments;
    $Self->{ 'UploadCacheFormID' . $FieldName }    = $UploadFieldUID;

    return \@Attachments;
}

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    # get the field value from the http request
    my $Values = $Self->EditFieldValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ParamObject        => $Param{ParamObject},

        # not necessary for this backend but place it for consistency reasons
        ReturnValueStructure => 1,
    );

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $ServerError;
    my %ErrorMessage;
    my %CheckFilenames;

    # perform necessary validations
    if ( $Param{Mandatory} && !IsArrayRefWithData($Values) && !IsHashRefWithData( $Values->[0] ) ) {
        my $Result = {
            ServerError  => 1,
            ErrorMessage => Translatable('This field is required.'),
        };
        return $Result;
    }
    else {

        # get maximum filesize values list
        my $MaximumFileSize  = $Param{DynamicFieldConfig}->{Config}->{MaximumFileSize} || 20;
        my $MaxFileSizeBytes = $MaximumFileSize * 1024 * 1024;
        my $UploadFieldUID   = $Self->{ 'UploadCacheFormID' . $FieldName };
        if ( !$UploadFieldUID ) {
            $UploadFieldUID = $Param{ParamObject}->GetParam( Param => "${FieldName}UID" );
            if ($UploadFieldUID) {
                $Self->{ 'UploadCacheFormID' . $FieldName } = $UploadFieldUID;
            }
            else {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "Couldn't get DynamicFieldUID!",
                );
                return {
                    ServerError => 1,
                };
            }
        }

        # Hash holding all deleted item's FileID's
        # needed to cleanup $Self->{ 'UploadCacheFilesMeta' . $FieldName } after file deletion
        # without doing an additional sql query, because UploadCacheObject doesn't cache it's meta contents
        my %Deleted;

        # get uploadcache object
        my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');

        # validate if value is in possible values list (but let pass empty values)
        VALUESLOOP:
        for my $Item ( @{$Values} ) {

            next VALUESLOOP if !$Item;

            # Check if a file with the same name already exists and delete it from the upload cache + error out
            if ( %CheckFilenames && $CheckFilenames{ $Item->{Filename} } ) {
                $Deleted{ $Item->{FileID} } = 1;
                $UploadCacheObject->FormIDRemoveFile(
                    FormID => $UploadFieldUID,
                    FileID => $Item->{FileID},
                );
                $ServerError = 1;
                push @{ $ErrorMessage{Filename} }, $Item->{Filename};
            }

            # If we are dealing with a value we already had in the Database
            # no validation
            my $FilesizeBytes = $Item->{Filesize} || 0;
            my $Filesize      = $Item->{Filesize};
            if ( $Filesize =~ s{([0-9,.]+) \s+ MBytes}{$1}xms ) {
                $FilesizeBytes = $1 * 1024 * 1024;
            }
            elsif ( $Filesize =~ s{([0-9,.]+)\s+KBytes}{$1}xms ) {
                $FilesizeBytes = $1 * 1024;
            }
            elsif ( $Filesize =~ s{([0-9,.]+)\s+Bytes}{$1}xms ) {
                $FilesizeBytes = $Filesize;
            }
            if ( !$FilesizeBytes ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "DynamicField Backend File could not detect file size!",
                );
                return {
                    ServerError => 1,
                };
            }

            if ( $FilesizeBytes > $MaxFileSizeBytes ) {
                $Deleted{ $Item->{FileID} } = 1;
                $UploadCacheObject->FormIDRemoveFile(
                    FormID => $UploadFieldUID,
                    FileID => $Item->{FileID},
                );
                $ServerError = 1;
                push @{ $ErrorMessage{Filesize} }, $Item->{Filename};
            }
            $CheckFilenames{ $Item->{Filename} } = 1;
        }

        # Now let's see if we had deleted items and remove them from the $Self->{ 'UploadCacheFilesMeta' . $FieldName }
        # StoredValues are not being deleted here, deletion will be done on save
        if (%Deleted) {
            @{ $Self->{ 'UploadCacheFilesMeta' . $FieldName } }
                = grep { $_->{StoredValue} || !$Deleted{ $_->{FileID} } } @{$Values};
        }
    }

    # create resulting structure
    my $Result = {
        ServerError  => $ServerError,
        ErrorMessage => \%ErrorMessage,
    };

    return $Result;
}

sub DisplayValueRender {
    my ( $Self, %Param ) = @_;

    # set HTMLOutput as default if not specified
    if ( !defined $Param{HTMLOutput} ) {
        $Param{HTMLOutput} = 1;
    }

    # set Value and Title variables
    my $Value         = '';
    my $Title         = '';
    my $ValueMaxChars = $Param{ValueMaxChars} || '';
    my $TitleMaxChars = $Param{TitleMaxChars} || '';

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }

    # return simple string if not HTMLOutput
    if ( !$Param{HTMLOutput} ) {

        # get specific field settings
        my $FieldConfig = $Kernel::OM->Get('Kernel::Config')->Get('DynamicFields::Driver')->{Attachment} || {};

        # set new line separator
        my $ItemSeparator = $FieldConfig->{ItemSeparator} || ', ';

        my @FileNames = map { $_->{Filename} } @Values;

        my $Value = join( $ItemSeparator, @FileNames );

        my $Data = {
            Value => $Value,
            Title => undef,
            Link  => undef,
        };

        return $Data;
    }

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # get real values
    my $PossibleValues     = $Param{DynamicFieldConfig}->{Config}->{PossibleValues};
    my $TranslatableValues = $Param{DynamicFieldConfig}->{Config}->{TranslatableValues};

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $Template  = <<'EOF';
[% RenderBlockStart("AttachmentHTML") %]
[% RenderBlockStart("AttachmentHTMLCSSAgent") %]
    <style type="text/css">
        #AttachmentLink[% Data.FieldName | html %] {
            cursor: pointer;
            display: block;
            height: 16px;
            width: 100px;
            padding-left: 5px !important;
        }
    </style>
[% RenderBlockEnd("AttachmentHTMLCSSAgent") %]
[% RenderBlockStart("AttachmentHTMLCSSCustomer") %]
    <style type="text/css">
        #AttachmentLink[% Data.FieldName | html %] {
            cursor: pointer;
            display: inline-block;
            height: 16px;
            width: 100px;
            padding-left: 5px !important;
        }
    </style>

[% RenderBlockEnd("AttachmentHTMLCSSCustomer") %]
[% RenderBlockStart("AttachmentIconSingle") %]
    <a id="AttachmentLink[% Data.FieldName | html %]" class="Attachment" title="[% Translate("Attachment") | html %] [% Data.Filename | html %] ([% Data.Filesize | Localize('Filesize') %])" rel="Attachment[% Data.FieldName | html %]">
        <i class="fa fa-paperclip"></i> [% Translate("Attachment") | html %]
    </a>
[% RenderBlockEnd("AttachmentIconSingle") %]
[% RenderBlockStart("AttachmentIconMultiple") %]
    <a id="AttachmentLink[% Data.FieldName | html %]" class="Attachment" title="[% Translate("Attachments") | html %]" rel="Attachment[% Data.FieldName | html %]">
        <i class="fa fa-paperclip"></i> [% Translate("Attachments") | html %]
    </a>
[% RenderBlockEnd("AttachmentIconMultiple") %]
    <div id="Attachment[% Data.FieldName | html %]" class="AttachmentData Hidden">
        <div style="height: 100%; width: 100%;" class="Attachment InnerContent">
[% RenderBlockStart("AttachmentRowLink") %]
            <div class="AttachmentElement">
                <h3>
EOF
    $Template .= '
                    <a href="[% Env("CGIHandle") %]?Action='
        . (
            $LayoutObject->{UserType} eq 'Customer'
            ? 'CustomerDynamicFieldAttachment'
            : 'AgentDynamicFieldAttachment'
        )
        . ';Filename=[% Data.Filename | uri %];DynamicFieldID=[% Data.DynamicFieldID | uri %];Object=[% Data.Object | uri %];ObjectID=[% Data.ObjectID | uri %]" target="attachment"[% Data.FieldClass | html %]>[% Data.Filename | html %]</a>';

    $Template .= <<'EOF';
                </h3>
                <p>[% Data.Filesize | Localize('Filesize') %]</p>
            </div>
[% RenderBlockEnd("AttachmentRowLink") %]
        </div>
    </div>
[% RenderBlockEnd("AttachmentHTML") %]
EOF

    $LayoutObject->Block(
        Name => 'AttachmentHTML',
        Data => {
            FieldName => $FieldName,
        },
    );

    if ( $LayoutObject->{UserType} eq 'Customer' ) {
        $LayoutObject->Block(
            Name => 'AttachmentHTMLCSSCustomer',
            Data => {
                FieldName => $FieldName,
            },
        );
    }
    else {
        $LayoutObject->Block(
            Name => 'AttachmentHTMLCSSAgent',
            Data => {
                FieldName => $FieldName,
            },
        );
    }

    if (@Values) {
        if ( scalar @Values == 1 ) {
            $LayoutObject->Block(
                Name => 'AttachmentIconSingle',
                Data => {
                    Filename  => $Values[0]->{Filename},
                    Filesize  => $Values[0]->{Filesize},
                    FieldName => $FieldName,
                },
            );
        }
        else {
            $LayoutObject->Block(
                Name => 'AttachmentIconMultiple',
                Data => {
                    FieldName => $FieldName,
                },
            );
        }

        for my $Item (@Values) {

            my $ObjectID;
            my $FieldID    = $Param{DynamicFieldConfig}->{ID};
            my $ObjectType = $Param{DynamicFieldConfig}->{ObjectType};
            my $FieldClass = '';
            if ( $Item->{StorageLocation} =~ /^DynamicField\/$FieldID\/$ObjectType\/(\d+)\// ) {
                $ObjectID = $1;
            }

            $LayoutObject->Block(
                Name => 'AttachmentRowLink',
                Data => {
                    Filename       => $Item->{Filename},
                    Filesize       => $Item->{Filesize},
                    FieldName      => $FieldName,
                    DynamicFieldID => $FieldID,
                    Object         => $ObjectType,
                    ObjectID       => $ObjectID,
                    FieldClass     => $FieldClass,
                },
            );
        }

        # article and ticket type are shown on different places over the screen
        if (
            $Param{DynamicFieldConfig}->{ObjectType} eq 'Article'
            )
        {
            my $JSCode = '
    $(document).on("click", "#AttachmentLink' . $FieldName . '", function (Event) {
        var Position, ScrollTop;
        if ($(this).attr("rel") && $("#" + $(this).attr("rel")).length) {
            Position = $(this).offset();
            ScrollTop = $(document).scrollTop();

            Core.UI.Dialog.ShowContentDialog($("#" + $(this).attr("rel"))[0].innerHTML, Core.Language.Translate("Attachments"), (Position.top - ScrollTop) + 25, parseInt(Position.left, 10));
        }
        Event.preventDefault();
        Event.stopPropagation();
        return false;
    });
            ';

            # add js to call FormUpdate()
            $LayoutObject->AddJSOnDocumentComplete( Code => $JSCode );

        }

        # else use the on_document_complete version
        else {

            my $JSCode = '

    $(document).on("click", "#AttachmentLink' . $FieldName . '", function (Event) {
        var Position, ScrollTop, PositionLeft, AttachmentBoxWidth;
        if ($(this).attr("rel") && $("#" + $(this).attr("rel")).length) {
            Position = $(this).offset();
            ScrollTop = $(document).scrollTop();
            AttachmentBoxWidth = parseInt(Math.ceil($("#" + $(this).attr("rel")).outerWidth()), 10);
            PositionLeft = Position.left;

            // Check if we need to adjust the position if the attachment box is bigger than the available space.
            if ( (PositionLeft + AttachmentBoxWidth) > $(window).width()) {
                PositionLeft = $(window).width() - AttachmentBoxWidth;
            }

            Core.UI.Dialog.ShowContentDialog($("#" + $(this).attr("rel"))[0].innerHTML, Core.Language.Translate("Attachments"), (Position.top - ScrollTop) + 25, PositionLeft );
        }
        Event.preventDefault();
        Event.stopPropagation();
        return false;
    });
            ';

            # add js to call FormUpdate()
            $LayoutObject->AddJSOnDocumentComplete( Code => $JSCode );

        }

    }
    my $Rendered = $LayoutObject->Output(
        Template => $Template,
    );

    my $Data = {
        Value => $Rendered,
        Title => undef,
        Link  => undef,
    };

    return $Data;
}

sub SearchFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    # set the field value
    my $Value = ( defined $Param{DefaultValue} ? $Param{DefaultValue} : '' );

    # get the field value, this function is always called after the profile is loaded
    my $FieldValue = $Self->SearchFieldValueGet(%Param);

    # set values from profile if present
    if ( defined $FieldValue ) {
        $Value = $FieldValue;
    }

    # check if value is an arrayref (GenericAgent Jobs and NotificationEvents)
    if ( IsArrayRefWithData($Value) ) {
        $Value = @{$Value}[0];
    }

    # check and set class if necessary
    my $FieldClass = 'DynamicFieldFile';

    my $HTMLString = <<"EOF";
<input type="text" class="$FieldClass" id="$FieldName" name="$FieldName" title="$FieldLabel" value="$Value" />
EOF

    my $AdditionalText;
    if ( $Param{UseLabelHints} ) {
        $AdditionalText = Translatable('e.g. Text or Te*t');
    }

    # call EditLabelRender on the base driver
    my $LabelString = $Self->EditLabelRender(
        %Param,
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        FieldName          => $FieldName,
        AdditionalText     => $AdditionalText,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub SearchFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $Value;

    # get dynamic field value form param object
    if ( defined $Param{ParamObject} ) {
        $Value = $Param{ParamObject}->GetParam(
            Param => 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name}
        );
    }

    # otherwise get the value from the profile
    elsif ( defined $Param{Profile} ) {
        $Value = $Param{Profile}->{ 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} };
    }
    else {
        return;
    }

    if ( defined $Param{ReturnProfileStructure} && $Param{ReturnProfileStructure} eq 1 ) {
        return {
            'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} => $Value,
        };
    }

    return $Value;

}

sub SearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # get field value
    my $Value = $Self->SearchFieldValueGet(%Param);

    # $Value holds an array ref with an empty string if we have to search for nothing
    # or the value we have to search for as string on the first position of the array
    if ( ref $Value eq 'ARRAY' && defined $Value->[0] ) {
        $Value = $Value->[0];
    }

    # If we didn't have a clean value to search for,
    # make sure we deal at least with an empty string
    else {
        $Value = '';
    }

    # set operator
    my $Operator = 'Like';

    # search for a wild card in the value
    if ( length $Value ) {
        $Value = '%Filename: ' . $Value . '%';
    }

    # return search parameter structure
    return {
        Parameter => {
            $Operator => $Value,
        },
        Display => $Value,
    };
}

sub StatsFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    return {
        Name    => $Param{DynamicFieldConfig}->{Label},
        Element => 'DynamicField_' . $Param{DynamicFieldConfig}->{Name},
    };
}

sub CommonSearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    my $Value = $Param{Value};

    # set operator
    my $Operator = 'Like';

    # search for a wild card in the value
    if ( length $Value ) {
        $Value = '%Filename: ' . $Value . '%';
    }

    return {
        $Operator => $Value,
    };
}

sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    # set Value and Title variables
    my $Value = '';
    my $Title = '';

    # check value
    my @Values;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Values = @{ $Param{Value} };
    }

    my @ReadableValues;

    VALUEITEM:
    for my $Item (@Values) {
        next VALUEITEM if !$Item;

        push @ReadableValues, (
            $Item->{Filename} . ', '
                . $Item->{Filesize}
        );
    }

    # set new line separator
    my $ItemSeparator = '; ';

    # Output transformations
    $Value = join( $ItemSeparator, @ReadableValues );
    $Title = $Value;

    # cut strings if needed
    if ( $Param{ValueMaxChars} && length($Value) > $Param{ValueMaxChars} ) {
        $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
    }
    if ( $Param{TitleMaxChars} && length($Title) > $Param{TitleMaxChars} ) {
        $Title = substr( $Title, 0, $Param{TitleMaxChars} ) . '...';
    }

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
    };

    return $Data;
}

sub TemplateValueTypeGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # set the field types
    my $EditValueType   = 'ARRAY';
    my $SearchValueType = 'ARRAY';

    # return the correct structure
    if ( $Param{FieldType} eq 'Edit' ) {
        return {
            $FieldName => $EditValueType,
        };
    }
    elsif ( $Param{FieldType} eq 'Search' ) {
        return {
            'Search_' . $FieldName => $SearchValueType,
        };
    }
    else {
        return {
            $FieldName             => $EditValueType,
            'Search_' . $FieldName => $SearchValueType,
        };
    }
}

sub RandomValueSet {
    my ( $Self, %Param ) = @_;

    my $Value = int( rand(500) );

    # get a new upload cache object
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');

    # get a new form id
    my $FormID     = $UploadCacheObject->FormIDCreate();
    my $FormIDName = 'UploadCacheFormIDDynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # set new form id
    $Self->{$FormIDName} = $FormID;

    my $Success = $Self->ValueSet(
        %Param,
        Value => $Value,
    );

    if ( !$Success ) {
        return {
            Success => 0,
        };
    }
    return {
        Success => 1,
        Value   => $Value,
    };
}

sub ObjectMatch {
    my ( $Self, %Param ) = @_;

    my $FieldName = $Param{DynamicFieldConfig}->{Name};

    # not supported
    return 0;
}

sub ValueLookup {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Key} ? $Param{Key} : '';

    return $Value;
}

=item AttachmentDownload()

This function is used to get the output headers for the download

    my $Value = $BackendObject->AttachmentDownload(
        ObjectID           => $DynamicFieldObjectID,
        Object             => $DynamicFieldObject,  # Ticket or Article
        DynamicFieldID     => $DynamicFieldID,
        Filename           => $AttachmentFileName,
        DynamicFieldConfig => $DynamicFieldConfig,  # complete config of the DynamicField
        TicketObject       => $TicketObject,
        LayoutObject       => $LayoutObject,
    );

    Returns $Attachment;

=cut

sub AttachmentDownload {
    my ( $Self, %Param ) = @_;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check needed stuff
    for my $Needed (qw(ObjectID Object DynamicFieldID Filename DynamicFieldConfig)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return $LayoutObject->ErrorScreen();
        }
    }

    $Param{UserType} //= $LayoutObject->{UserType};

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $TicketID;
    my %Object;
    if ( $Param{Object} eq 'Article' ) {

        $TicketID = $Kernel::OM->Get('Kernel::System::Ticket::Article')->TicketIDLookup(
            ArticleID => $Param{ObjectID},
        );

        if ( !$TicketID ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Message  => "No TicketID for ArticleID ($Param{ObjectID})!",
                Priority => 'error',
            );
            return $LayoutObject->ErrorScreen();
        }
    }
    elsif ( $Param{Object} eq 'Ticket' ) {

        %Object = $TicketObject->TicketGet(
            TicketID      => $Param{ObjectID},
            DynamicFields => 0,
            UserID        => 1,
        );
        if ( !$Object{TicketID} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Message  => "No Ticket found for ID ($Param{ObjectID})!",
                Priority => 'error',
            );
            return $LayoutObject->ErrorScreen();
        }
        $TicketID = $Object{TicketID};
    }
    else {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Message  => "Could not determine Object for $Param{Object}!",
            Priority => 'error',
        );
        return $LayoutObject->ErrorScreen();
    }

    # check permissions
    my $Access;
    if ( $Param{UserType} eq 'Customer' || $LayoutObject->{UserType} eq 'Customer' ) {
        $Access = $TicketObject->TicketCustomerPermission(
            Type     => 'ro',
            TicketID => $TicketID,
            UserID   => $Param{UserID}
        );
    }
    else {
        $Access = $TicketObject->TicketPermission(
            Type     => 'ro',
            TicketID => $TicketID,
            UserID   => $Param{UserID}
        );
    }

    if ( !$Access ) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' );
    }

    if ( !IsHashRefWithData( $Param{DynamicFieldConfig} ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Message =>
                "No DynamicField config found for DynamicFieldID $Param{DynamicFieldID} and Object $Param{Object}!",
            Priority => 'error',
        );
        return $LayoutObject->ErrorScreen();
    }

    my $Attachment = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->ValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ObjectID           => $Param{ObjectID},
        Download           => 1,
        Filename           => $Param{Filename},
    );

    if ( !IsHashRefWithData($Attachment) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Message  => "Could not get file named $Param{Filename}!",
            Priority => 'error',
        );
        return $LayoutObject->ErrorScreen();
    }

    return $Attachment if $Param{UserType} eq 'Customer' && $Param{Action} ne 'CustomerDynamicFieldAttachment';

    return $LayoutObject->Attachment(
        %{$Attachment},
        Type => 'attachment',
    );
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTOBO project (L<https://otobo.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
