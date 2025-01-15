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

package Kernel::Language::hu_OTOBODynamicFieldAttachment;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    # Template: AdminDynamicFieldAttachment
    $Self->{Translation}->{'Field'}                         = 'Mező';
    $Self->{Translation}->{'Maximum amount of attachments'} = 'Mellékletek legnagyobb száma';
    $Self->{Translation}->{'Change this, if you need more or less attachments to be stored in this dynamic field.'} =
        'Változtassa meg, ha több vagy kevesebb mellékletet szükséges tárolni ebben a dinamikus mezőben.';
    $Self->{Translation}->{'Maximum attachment size'} = 'Legnagyobb mellékletméret';
    $Self->{Translation}->{'Maximum size per attachment in MB for this dynamic field. 0 for no limit.'} =
        'Legnagyobb méret mellékletenként MB-ban ennél a dinamikus mezőnél. A 0 azt jelenti, hogy nincs korlát.';

    # Perl Module: Kernel/Modules/AdminDynamicFieldAttachment.pm
    $Self->{Translation}->{'The maximum of attachments for this dynamic field of type attachment must be a positive number.'} =
        'A mellékletek legnagyobb számának ennél a melléklet típusú dinamikus mezőnél pozitív számnak kell lennie.';
    $Self->{Translation}->{'The maximum attachment size for this dynamic field of type attachment must be a positive number.'} =
        'A legnagyobb mellékletméretnek ennél a melléklet típusú dinamikus mezőnél pozitív számnak kell lennie.';
    $Self->{Translation}->{'Need ValidID!'}                            = 'Érvényességazonosító szükséges!';
    $Self->{Translation}->{'Could not create the new field.'}          = 'Nem sikerült létrehozni az új mezőt.';
    $Self->{Translation}->{'Need ID!'}                                 = 'Azonosító szükséges!';
    $Self->{Translation}->{'Could not get data for dynamic field %s!'} = 'Nem sikerült lekérni az adatokat a(z) %s dinamikus mezőhöz!';
    $Self->{Translation}->{'Could not update the field %s!'}           = 'Nem sikerült frissíteni a(z) %s mezőt!';

    # JS File: Core.Agent.DynamicField.Attachment
    $Self->{Translation}->{'Disable Attachments'} = 'Mellékletek letiltása';

    # SysConfig
    $Self->{Translation}->{'Dynamic Fields Attachment Backend GUI'}       = 'Melléklet dinamikus mezők háttérprogram grafikus felhasználói felület';
    $Self->{Translation}->{'Dynamic Fields Attachment download frontend'} = 'Melléklet dinamikus mezők letöltés előtétprogram';
    $Self->{Translation}->{'Dynamic field backend registration.'}         = 'Dinamikus mező háttérprogram regisztráció.';
    $Self->{Translation}->{'Dynamic fields extension.'}                   = 'Dinamikus mező kiterjesztés.';
    $Self->{Translation}->{'Frontend module registration for the admin interface.'} = 'Előtétprogram-modul regisztráció az adminisztrátori felülethez.';

    push @{ $Self->{JavaScriptStrings} // [] }, (
        'Cancel',
        'Delete',
        'Disable',
        'Disable Attachments',
    );

}

1;
