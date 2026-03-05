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

package Kernel::Language::de_DynamicFieldAttachment;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    # Template: AdminDynamicFieldAttachment
    $Self->{Translation}->{'Maximum amount of attachments'} = 'Maximale Anzahl an Anhängen';
    $Self->{Translation}->{'Change this, if you need more or less attachments to be stored in this dynamic field.'} =
        'Ändern Sie diese Einstellung, wenn Sie mehr oder weniger Dokumente in dieses DynamicField speichern wollen.';
    $Self->{Translation}->{'Maximum attachment size'} = 'Maximale Dateigröße';
    $Self->{Translation}->{'Maximum size per attachment in MB for this dynamic field. 0 for no limit.'} =
        'Maximale Größe pro Anhang in MB für dieses DynamicField. 0 für keine Beschränkung.';

    # Perl Module: Kernel/Modules/AdminDynamicFieldAttachment.pm
    $Self->{Translation}->{'Dynamic field Attachment is not implemented for object type %s!'} =
        '';
    $Self->{Translation}->{'The maximum of attachments for this dynamic field of type attachment must be a positive integer.'} =
        '';
    $Self->{Translation}->{'The maximum attachment size for this dynamic field of type attachment must be a positive integer.'} =
        '';
    $Self->{Translation}->{'The maximum of attachments for this dynamic field of type attachment must be a positive number.'} =
        'Die maximale Anzahl der Anhänge muss eine positive Ganzzahl sein.';
    $Self->{Translation}->{'The maximum attachment size for this dynamic field of type attachment must be a positive number.'} =
        'Die maximale Größe jedes Anhangs muss eine positive Ganzzahl sein.';

    # JS File: Core.Agent.DynamicField.Attachment
    $Self->{Translation}->{'Disable Attachments'} = 'Anhänge deaktivieren';

    # SysConfig
    $Self->{Translation}->{'Dynamic Fields Attachment Backend GUI'} = 'Dynamic Fields-Oberfläche für Anhänge';
    $Self->{Translation}->{'Dynamic Fields Attachment download frontend'} = 'Dynamic Fields-Download-Frontend für Anhänge';
    $Self->{Translation}->{'Dynamic field backend registration.'} = 'Backend-Registrierung für dynamische Felder.';
    $Self->{Translation}->{'Dynamic fields extension.'} = 'Dynamische Felder Erweiterung.';
    $Self->{Translation}->{'List of css files to always be loaded for the customer interface.'} =
        '';


    push @{ $Self->{JavaScriptStrings} // [] }, (
    'Cancel',
    'Delete',
    'Disable',
    'Disable Attachments',
    );

}

1;
