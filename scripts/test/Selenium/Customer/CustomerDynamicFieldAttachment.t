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

use strict;
use warnings;
use utf8;

use Kernel::System::UnitTest::RegisterDriver;    # Set up $Kernel::OM and $main::Self
use Kernel::System::UnitTest::Selenium;

# get selenium object
my $Selenium = Kernel::System::UnitTest::Selenium->new( LogExecuteCommandActive => 1 );

our $Self;

$Selenium->RunTest(
    sub {

        # get helper objects
        my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

        # enable RichText
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Frontend::RichText',
            Value => 1,
        );

        # do not check service and type
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Ticket::Service',
            Value => 0,
        );
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Ticket::Type',
            Value => 0,
        );

        # get dynamic field object
        my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

        # define random ID
        my $RandomID = $Helper->GetRandomID();

        # create test dynamic field attachment for ticket
        my $TicketDynamicFieldName = 'TicketDFAttachment' . $RandomID;
        my $TicketDynamicFieldID   = $DynamicFieldObject->DynamicFieldAdd(
            Name       => $TicketDynamicFieldName,
            Label      => $TicketDynamicFieldName,
            FieldOrder => 9991,
            FieldType  => 'Attachment',
            ObjectType => 'Ticket',
            Config     => {
                MaximumFileSize => 20,
                NumberOfFiles   => 10,
                Undeletable     => 1
            },
            ValidID => 1,
            UserID  => 1,
        );
        $Self->True(
            $TicketDynamicFieldID,
            "Dynamic field $TicketDynamicFieldName - ID $TicketDynamicFieldID is created",
        );

        # create test dynamic field attachment for article
        my $ArticleDynamicFieldName = 'ArticleDFAttachment' . $RandomID;
        my $ArticleDynamicFieldID   = $DynamicFieldObject->DynamicFieldAdd(
            Name       => $ArticleDynamicFieldName,
            Label      => $ArticleDynamicFieldName,
            FieldOrder => 9992,
            FieldType  => 'Attachment',
            ObjectType => 'Article',
            Config     => {
                MaximumFileSize => 20,
                NumberOfFiles   => 10,
                Undeletable     => 1
            },
            ValidID => 1,
            UserID  => 1,
        );
        $Self->True(
            $ArticleDynamicFieldID,
            "Dynamic field $ArticleDynamicFieldID - ID $ArticleDynamicFieldID is created",
        );

        # set test dynamic field attachment to show in CustomerNewMessage and CustomerZoom screen
        for my $SysConfig (qw(Message Zoom)) {
            $Helper->ConfigSettingChange(
                Valid => 1,
                Key   => 'Ticket::Frontend::CustomerTicket' . $SysConfig . '###DynamicField',
                Value => {
                    $TicketDynamicFieldName  => 1,
                    $ArticleDynamicFieldName => 1,
                },
            );
        }

        # add some queues, if there have not been created before
        my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
        my %Queues;
        for my $QueueName (qw(Sales Marketing Marketing::Events GMS GMS::GlobalServiceDesk)) {

            my $QueueID = $QueueObject->QueueLookup( Queue => $QueueName );
            if ( !$QueueID ) {
                $QueueID = $QueueObject->QueueAdd(
                    Name            => $QueueName,
                    ValidID         => 1,
                    GroupID         => 1,
                    SystemAddressID => 1,
                    SalutationID    => 1,
                    SignatureID     => 1,
                    Comment         => 'Some comment',
                    UserID          => 1,
                );

                $Self->True(
                    $QueueID,
                    "Queue $QueueName is created - $QueueID",
                );

                $Queues{$QueueName}{CreatedNow} = 1;
            }
            else {

                $Self->True(
                    $QueueID,
                    "Queue $QueueName has been created before - $QueueID",
                );

                # in some system there could exist some of the standard queues for OTOBOCustomerPortal
                $Queues{$QueueName}{CreatedNow} = 0;
            }
            $Queues{$QueueName}{ID}   = $QueueID;
            $Queues{$QueueName}{Name} = $QueueName;
        }

        # create test user and login
        my $TestCustomerUserLogin = $Helper->TestCustomerUserCreate(
        ) || die "Did not get test customer user";

        $Selenium->Login(
            Type     => 'Customer',
            User     => $TestCustomerUserLogin,
            Password => $TestCustomerUserLogin,
        );

        # get config object
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

        # get script alias
        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        # navigate to CustomerTicketMessage screen
        $Selenium->VerifiedGet("${ScriptAlias}customer.pl?Action=CustomerTicketMessage");

        # try to create test ticket with dynamic field attachment with two same attachment
        my $TicketDFAttchFile  = 'StdAttachment-Test1.txt';
        my $ArticleDFAttchFile = 'StdAttachment-Test1.doc';
        my $TicketDFAttchLocation
            = $ConfigObject->Get('Home') . "/scripts/test/sample/StdAttachment/$TicketDFAttchFile";
        my $ArticleDFAttchLocation
            = $ConfigObject->Get('Home') . "/scripts/test/sample/StdAttachment/$ArticleDFAttchFile";

        my $TicketSubject = "Selenium Ticket";
        my $TicketBody    = "Selenium body test";

        $Selenium->execute_script(
            "\$('#Dest').val('$Queues{'Sales'}{ID}||$Queues{'Sales'}{Name}').trigger('redraw.InputField').trigger('change');"
        );
        sleep 2;

        $Selenium->find_element( "#Subject", 'css' )->send_keys($TicketSubject);
        $Selenium->execute_script("CKEditorInstances['RichText'].setData(\"' . $TicketBody . '\");");

        # we wait a second to make sure the content has been set correctly
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function";' );
        sleep 1;

        # Check DnDUpload.
        my $Element = $Selenium->find_element( ".DnDUpload", 'css' );
        $Element->is_enabled();
        $Element->is_displayed();

        # Hide DnDUpload and show input field.
        $Selenium->execute_script(
            "\$('.DnDUpload').css('display', 'none')"
        );
        $Selenium->execute_script(
            "\$('#DynamicField_$TicketDynamicFieldName').css('display', 'block')"
        );
        $Selenium->execute_script(
            "\$('#DynamicField_$ArticleDynamicFieldName').css('display', 'block')"
        );
        sleep 2;

        # add two same attachment in DynamicField
        $Selenium->find_element( "#DynamicField_$TicketDynamicFieldName", 'css' )->clear();
        $Selenium->find_element( "#DynamicField_$TicketDynamicFieldName", 'css' )->send_keys($TicketDFAttchLocation);

        # wait until form is updated, if necessary
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $(".AttachmentList").length' );

        # Wait before adding the second attachment, because of some problems with chrome.
        sleep 2;

        $Selenium->find_element( "#DynamicField_$TicketDynamicFieldName", 'css' )->send_keys($TicketDFAttchLocation);

        $Selenium->WaitFor(
            JavaScript => 'return typeof($) === "function" && $(".Dialog:visible").length === 1;'
        );

        # Verify dialog message.
        my $UploadAgainMessage
            = "The following files were already uploaded and have not been uploaded again: StdAttachment-Test1.txt";
        $Self->True(
            $Selenium->execute_script(
                "return \$('.Dialog.Modal .InnerContent:contains(\"$UploadAgainMessage\")').length"
            ),
            "UploadAgainMessage is found - Attachment with same name found",
        );

        # Confirm dialog action.
        $Selenium->find_element( "#DialogButton1",                        'css' )->click();
        $Selenium->find_element( "#DynamicField_$TicketDynamicFieldName", 'css' )->clear();

        # delete the remaining file
        $Self->Is(
            $Selenium->execute_script(
                "return \$('.AttachmentList tbody tr td.Filename:contains(StdAttachment-Test1.txt)').length"
            ),
            1,
            "Uploaded 'txt' file still there"
        );

        # Delete Attachment.
        $Selenium->execute_script(
            "\$('.AttachmentList tbody tr:contains(StdAttachment-Test1.txt)').find('a.AttachmentDelete').trigger('click')"
        );

        # Wait until attachment is deleted.
        $Selenium->WaitFor(
            JavaScript =>
                'return typeof($) === "function" && $(".fa.fa-spinner.fa-spin:visible").length === 0;'
        );

        # Check if deleted.
        $Self->Is(
            $Selenium->execute_script(
                "return \$('.AttachmentList tbody tr td.Filename:contains(StdAttachment-Test1.txt)').length"
            ),
            0,
            "Upload 'txt' file deleted"
        );

        # add first attachment again
        $Selenium->find_element( "#DynamicField_$TicketDynamicFieldName", 'css' )->send_keys($TicketDFAttchLocation);

        # add ArticleDynamicFieldAttachment
        $Selenium->find_element( "#DynamicField_$ArticleDynamicFieldName", 'css' )->send_keys($ArticleDFAttchLocation);

        # submit ticket again
        $Selenium->execute_script('$("#submitRichText").click();');
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $(".TicketView .Overview").length' );

        # get ticket object
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # get created test ticket ID and number
        my %TicketIDs = $TicketObject->TicketSearch(
            Result         => 'HASH',
            Limit          => 1,
            CustomerUserID => $TestCustomerUserLogin,
        );
        my $TicketNumber = (%TicketIDs)[1];
        my $TicketID     = (%TicketIDs)[0];

        $Self->True(
            $TicketID,
            "Ticket was created and found",
        );

        $Self->True(
            index( $Selenium->get_page_source(), $TicketNumber ) > -1,
            "TicketID $TicketID is created",
        );

        # go to ticket zoom page of created test ticket
        $Selenium->VerifiedGet("${ScriptAlias}customer.pl?Action=CustomerTicketZoom;TicketNumber=$TicketNumber");

        # click on TicketDynamicFieldAttachment in CustomerTicketZoom screen
        $Selenium->find_element( "#AttachmentLinkDynamicField_$TicketDynamicFieldName", 'css' )->click();

        # wait for dialog to show up
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $(".Dialog").length' );

        # verify elements from TicketDynamicFieldAttachment dialog
        my $TicketDialogElement = $Selenium->find_element( ".Dialog", 'css' );
        for my $TicketChildElements (qw(Header Content Attachment AttachmentElement)) {
            $Selenium->find_child_element( $TicketDialogElement, ".$TicketChildElements", 'css' );
        }

        # verify there is actual attachment in TicketDynamicFiledAttachment
        my $TicketDFAttachment = $Selenium->find_element(
            "//a[contains(\@href, 'CustomerDynamicFieldAttachment;Filename=$TicketDFAttchFile;')]"
        );
        $Self->True(
            $TicketDFAttachment,
            "Attachment $TicketDFAttchFile found in TicketDynamicFieldAttachment",
        );

        # close TicketDynamicFieldAttachment dialog
        $Selenium->find_child_element( $TicketDialogElement, ".Close", 'css' )->click();

        # wait for dialog to go away
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && !$(".Dialog").length' );

        # click on ArticleDynamicFieldAttachment in CustomerZoom screen
        $Selenium->find_element( "#AttachmentLinkDynamicField_$ArticleDynamicFieldName", 'css' )->click();

        # wait for dialog to show up
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $(".Dialog").length' );

        # verify elements from ArticleDynamicFieldAttachment dialog
        my $ArticleDialogElement = $Selenium->find_element( ".Dialog", 'css' );
        for my $ArticleDFChildElements (qw(Header Content Attachment AttachmentElement)) {
            $Selenium->find_child_element( $ArticleDialogElement, ".$ArticleDFChildElements", 'css' );
        }

        # verify there is actual attachment in ArticleDynamicFiledAttachment
        my $ArticleDFAttachment = $Selenium->find_element(
            "//a[contains(\@href, 'CustomerDynamicFieldAttachment;Filename=$ArticleDFAttchFile;')]"
        );
        $Self->True(
            $ArticleDFAttachment,
            "Attachment $ArticleDFAttchFile found in ArticleDynamicFieldAttachment",
        );

        # close ArticleDynamicFieldAttachment dialog
        $Selenium->find_child_element( $ArticleDialogElement, ".Close", 'css' )->click();

        # wait for dialog to go away
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && !$(".Dialog").length' );

        # clean up
        # delete created test ticket
        my $Success = $TicketObject->TicketDelete(
            TicketID => $TicketID,
            UserID   => 1,
        );
        $Self->True(
            $Success,
            "TicketID $TicketID is deleted",
        );

        # delete created test dynamic field
        for my $DynamicFieldDelete ( $TicketDynamicFieldID, $ArticleDynamicFieldID ) {
            $Success = $DynamicFieldObject->DynamicFieldDelete(
                ID     => $DynamicFieldDelete,
                UserID => 1,
            );
            $Self->True(
                $Success,
                "DynamicFieldAttachmentID $DynamicFieldDelete is deleted"
            );
        }

        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        QUEUE:
        for my $Queue ( sort keys %Queues ) {

            next QUEUE if !$Queues{$Queue}{CreatedNow};

            $Success = $DBObject->Do(
                SQL => "DELETE FROM queue WHERE id = $Queues{$Queue}{ID}",
            );
            $Self->True(
                $Success,
                "Queue is deleted - $Queues{$Queue}{ID}",
            );
        }

        for my $Cache (qw (Ticket* DynamicField Queue)) {
            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
                Type => $Cache,
            );
        }

    }

);

$Self->DoneTesting();
