# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
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

package Kernel::Modules::AgentDynamicFieldAttachment;

use strict;
use warnings;

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

    # Object permission are checked inside AttachmentDownload

    # get needed objects
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my %DownloadParams;
    for my $Item (qw(DynamicFieldID Object ObjectID Filename)) {
        my $Value = $ParamObject->GetParam( Param => $Item ) || '';
        if ( !$Value ) {
            return $LayoutObject->ErrorScreen(
                Message => $LayoutObject->{LanguageObject}->Translate( 'Need %s!', $Item ),
                Comment => Translatable('Please contact the administrator.'),
            );
        }
        $DownloadParams{$Item} = $Value;
    }

    $DownloadParams{DynamicFieldConfig} = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
        ID => $DownloadParams{DynamicFieldID},
    );

    # get download for attachment parameters
    return $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->AttachmentDownload(
        %{$Self},
        %DownloadParams,
    );
}

1;
