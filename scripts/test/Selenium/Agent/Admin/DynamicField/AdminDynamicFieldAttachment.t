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

our $Self;

# get selenium object
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        # get helper object
        my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

        my %DynamicFieldsOverviewPageShownSysConfig = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingGet(
            Name => 'PreferencesGroups###DynamicFieldsOverviewPageShown',
        );

        # show more dynamic fields per page as the default value
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'PreferencesGroups###DynamicFieldsOverviewPageShown',
            Value => {
                %{ $DynamicFieldsOverviewPageShownSysConfig{EffectiveValue} },
                DataSelected => 999,
            },
        );

        # create test user and login
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => ['admin'],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get script alias
        my $ScriptAlias = $Kernel::OM->Get('Kernel::Config')->Get('ScriptAlias');

        # navigate to AdminDynamiFied screen
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AdminDynamicField");

        # create DynamicFieldAttachment for ticket and article
        for my $Type (qw(Ticket Article)) {

            my $ObjectType = $Type . "DynamicField";
            my $Element    = $Selenium->find_element( "#$ObjectType option[value=Attachment]", 'css' );
            $Element->is_enabled();

            # create a real test DynamicFieldAttachment
            my $DynamicFieldName = $Helper->GetRandomID();
            $Selenium->execute_script(
                "\$('#$ObjectType').val('Attachment').trigger('redraw.InputField').trigger('change');"
            );

            # wait until page has finished loading
            $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $("#Name").length' );

            # input fields
            $Selenium->find_element( "#Name",            'css' )->send_keys($DynamicFieldName);
            $Selenium->find_element( "#Label",           'css' )->send_keys($DynamicFieldName);
            $Selenium->find_element( "#NumberOfFiles",   'css' )->clear();
            $Selenium->find_element( "#NumberOfFiles",   'css' )->send_keys(10);
            $Selenium->find_element( "#MaximumFileSize", 'css' )->clear();
            $Selenium->find_element( "#MaximumFileSize", 'css' )->send_keys(15);
            $Selenium->execute_script("\$('#ValidID').val('1').trigger('redraw.InputField').trigger('change');");
            $Selenium->find_element( "#Name", 'css' )->VerifiedSubmit();

            # check if test created DynamicFieldAttachment show on AdminDynamicField screen
            $Self->True(
                index( $Selenium->get_page_source(), $DynamicFieldName ) > -1,
                "$DynamicFieldName Attachment $Type DynamicField found on page",
            );

            # click on test created DynamicFieldAttachment, update it and set it to invalid status
            $Selenium->find_element( $DynamicFieldName, 'link_text' )->VerifiedClick();
            $Selenium->find_element( "#Label",          'css' )->clear();
            $Selenium->find_element( "#Label",          'css' )->send_keys( $DynamicFieldName . "-update" );
            $Selenium->execute_script("\$('#ValidID').val('2').trigger('redraw.InputField').trigger('change');");
            $Selenium->find_element( "#Name", 'css' )->VerifiedSubmit();

            # check class of invalid DynamicFieldAttachment in the overview table
            $Self->True(
                $Selenium->execute_script(
                    "return \$('tr.Invalid td a:contains($DynamicFieldName)').length"
                ),
                "There is a class 'Invalid' for test DynamicField",
            );

            # go to test created DynamicFieldAttachment again after update and check values
            $Selenium->find_element( $DynamicFieldName, 'link_text' )->VerifiedClick();

            # check test created DynamicFieldAttachment values
            $Self->Is(
                $Selenium->find_element( '#Name', 'css' )->get_value(),
                $DynamicFieldName,
                "#Name stored value",
            );
            $Self->Is(
                $Selenium->find_element( '#Label', 'css' )->get_value(),
                $DynamicFieldName . "-update",
                "#Label stored value",
            );
            $Self->Is(
                $Selenium->find_element( '#NumberOfFiles', 'css' )->get_value(),
                10,
                "#NumberOfFiles stored value",
            );
            $Self->Is(
                $Selenium->find_element( '#MaximumFileSize', 'css' )->get_value(),
                15,
                "#ValidID stored value",
            );
            $Self->Is(
                $Selenium->find_element( '#ValidID', 'css' )->get_value(),
                2,
                "#ValidID stored value",
            );

            # navigate to AdminDynamicField screen again
            $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AdminDynamicField");

            # delete DynamicFieldAttachment, check button for deleting Dynamic Field
            my $DynamicFieldID = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
                Name => $DynamicFieldName
            )->{ID};

            # click on delete icon
            my $CheckConfirmJSBlock = <<"JAVASCRIPT";
(function () {
var lastConfirm = undefined;
window.confirm = function (message) {
    lastConfirm = message;
    return false; // stop procedure at first try
};
window.getLastConfirm = function () {
    var result = lastConfirm;
    lastConfirm = undefined;
    return result;
};
}());
JAVASCRIPT
            $Selenium->execute_script($CheckConfirmJSBlock);

            $Selenium->find_element(
                "//a[contains(\@data-query-string, \'Subaction=DynamicFieldDelete;ID=$DynamicFieldID' )]"
            )->click();

            $Self->Is(
                $Selenium->execute_script("return window.getLastConfirm()"),
                'Do you really want to delete this dynamic field? ALL associated data will be LOST!',
                'Check for opened confirm text',
            );

            my $CheckConfirmJSProceed = <<"JAVASCRIPT";
(function () {
var lastConfirm = undefined;
window.confirm = function (message) {
    lastConfirm = message;
    return true; // allow procedure at second try
};
window.getLastConfirm = function () {
    var result = lastConfirm;
    lastConfirm = undefined;
    return result;
};
}());
JAVASCRIPT
            $Selenium->execute_script($CheckConfirmJSProceed);

            $Selenium->find_element(
                "//a[contains(\@data-query-string, \'Subaction=DynamicFieldDelete;ID=$DynamicFieldID' )]"
            )->VerifiedClick();

            # wait for delete dialog to disappear
            $Selenium->WaitFor(
                JavaScript => 'return typeof($) === "function" && $(".Dialog:visible").length === 0;'
            );

            # check if dynamic filed is deleted
            $Self->True(
                index( $Selenium->get_page_source(), $DynamicFieldName ) == -1,
                "$DynamicFieldName dynamic field is deleted!",
            );

        }

        # make sure the cache is correct
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp( Type => "DynamicField" );

    }

);

1;
