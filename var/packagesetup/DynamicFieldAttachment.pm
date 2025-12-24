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

package var::packagesetup::DynamicFieldAttachment;

use v5.24;
use strict;
use warnings;
use namespace::autoclean;
use utf8;

# core modules

# CPAN modules

# OTOBO modules
use Kernel::Language              qw(Translatable);
use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData);

our @ObjectDependencies = (
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Log',
);

=head1 NAME

var::packagesetup::DynamicFieldAttachment - code to execute during package installation

=head1 DESCRIPTION

Functions for installing the DynamicFieldAttachment package.

=head1 PUBLIC INTERFACE

=head2 new()

create an object

    use Kernel::System::ObjectManager;

    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CodeObject = $Kernel::OM->Get('var::packagesetup::ITSMConfigurationManagement');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = bless {}, $Type;

    # Force a reload of ZZZAuto.pm and ZZZAAuto.pm to get the fresh configuration values.
    for my $Module ( sort keys %INC ) {
        if ( $Module =~ m/ZZZAA?uto\.pm$/ ) {
            delete $INC{$Module};
        }
    }

    # Create common objects with fresh default config.
    $Kernel::OM->ObjectsDiscard();

    return $Self;
}

=head2 CodeUninstall()

run the code uninstall part

    my $Result = $CodeObject->CodeUninstall();

=cut

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    # delete all dynamic fields:
    #   of field type Attachment
    $Self->_DynamicFieldsDelete();

    return 1;
}

=head2 _DynamicFieldsDelete()

Deletes the dynamic fields which are related to this package, because they are of field type Attachment.

    my $Result = $CodeObject->_DynamicFieldsDelete();

=cut

sub _DynamicFieldsDelete {
    my ( $Self, %Param ) = @_;

    # get necessary objects
    my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $LogObject                 = $Kernel::OM->Get('Kernel::System::Log');

    # get all dynamic fields because we can't filter for field type in dynamic field list functions
    my $DynamicFields = $DynamicFieldObject->DynamicFieldListGet(
        Valid => 0,
    );

    DYNAMICFIELD:
    for my $DynamicFieldConfig ( $DynamicFields->@* ) {
        next DYNAMICFIELD unless IsHashRefWithData($DynamicFieldConfig);
        next DYNAMICFIELD unless $DynamicFieldConfig->{FieldType} eq 'Attachment';

        if ( $DynamicFieldConfig->{InternalField} ) {
            $LogObject->Log(
                'Priority' => 'error',
                'Message'  => "Could not delete internal DynamicField $DynamicFieldConfig->{Name}!",
            );
            next DYNAMICFIELD;
        }

        my $ValuesDeleteSuccess = $DynamicFieldBackendObject->AllValuesDelete(
            DynamicFieldConfig => $DynamicFieldConfig,
            UserID             => 1,
        );

        if ( !$ValuesDeleteSuccess ) {
            $LogObject->Log(
                'Priority' => 'error',
                'Message'  => "Could not delete values for DynamicField $DynamicFieldConfig->{Name}!",
            );
            next DYNAMICFIELD;
        }

        my $Success = $DynamicFieldObject->DynamicFieldDelete(
            ID     => $DynamicFieldConfig->{ID},
            UserID => 1,
        );

        if ( !$Success ) {
            $LogObject->Log(
                'Priority' => 'error',
                'Message'  => "Could not delete DynamicField $DynamicFieldConfig->{Name}!",
            );
            next DYNAMICFIELD;
        }
    }

    return 1;
}

1;
