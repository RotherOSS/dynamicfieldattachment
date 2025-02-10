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

package Kernel::Modules::AjaxDynamicFieldAttachment;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get param object
    my $ParamObject       = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
    my $LayoutObject      = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # get form id
    $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'FormID' );

    if ( !$Self->{FormID} ) {
        return $LayoutObject->FatalError(
            Message => Translatable('Got no FormID.'),
        );
    }

    # challenge token check for write action
    $LayoutObject->ChallengeTokenCheck();

    if ( $Self->{Subaction} eq 'Delete' ) {

        my $Return;
        my $AttachmentFileID   = $ParamObject->GetParam( Param => 'FileID' )   || '';
        my $AttachmentObjectID = $ParamObject->GetParam( Param => 'ObjectID' ) || '';
        my $AttachmentFieldID  = $ParamObject->GetParam( Param => 'FieldID' )  || '';

        if ( !$AttachmentFileID ) {
            $Return->{Message} = $LayoutObject->{LanguageObject}->Translate(
                'Error: the file could not be deleted properly. Please contact your administrator (missing FileID).'
            );
        }
        else {

            # get the dynamic fields for this screen
            my $DynamicField = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
                Valid => 1,
            );

            # get dynamic field backend object
            my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

            # cycle trough the activated Dynamic Fields for this screen
            DYNAMICFIELD:
            for my $DynamicFieldConfig ( @{$DynamicField} ) {

                next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
                next DYNAMICFIELD if $DynamicFieldConfig->{ID} ne $AttachmentFieldID;

                my $RemainingAttachments = $DynamicFieldBackendObject->SingleValueDelete(
                    DynamicFieldConfig => $DynamicFieldConfig,
                    FileID             => $AttachmentFileID,
                    ObjectID           => $AttachmentObjectID,
                    FieldID            => $AttachmentFieldID,
                    UserID             => $Self->{UserID},
                );

                $Return = {
                    Message => Translatable('Success'),
                    Data    => $RemainingAttachments,
                };

                last DYNAMICFIELD;
            }
        }

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $Kernel::OM->Get('Kernel::System::JSON')->Encode(
                Data => $Return,
            ),
            Type    => 'inline',
            NoCache => 1,
        );
    }
}

1;
