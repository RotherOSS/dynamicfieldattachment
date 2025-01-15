// --
// OTOBO is a web-based ticketing system for service organisations.
// --
// Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
// Copyright (C) 2019-2025 Rother OSS GmbH, https://otobo.io/
// --
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later version.
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};
Core.Agent.DynamicField = Core.AgentDynamicField || {};

/**
 * @namespace
 * @exports TargetNS as Core.Agent.DynamicField.Attachment
 * @description
 *      This namespace contains functions for all ticket action popups.
 */
Core.Agent.DynamicField.Attachment = (function (TargetNS){

    var filevalues = [];

    /**
     * @name Init
     * @memberof Core.Agent.DynamicField
     * @function
     * @description
     *      Initializes Overview screen.
     */
    TargetNS.Init = function () {

        $('.ShowWarning').on('change keyup', function () {
            $('p.Warning').removeClass('Hidden');
        });
// Rother OSS / Customer Interface
        if ( Core.Config.Get('SessionName') === Core.Config.Get('CustomerPanelSessionName') ) {
            $('.Row > .Field > .DFAttachments').each( function() {
                var Parent = $(this).parent();
                Parent.replaceWith( Parent.contents() );
            });
        }
// EO Customer Interface
    };

    /*
     * @function
     * @description
     *      This function initializes the DynamicField.Attachment functions
     * @return nothing
     */
    TargetNS.AddField = function(){
        // Find all upload fields in our div
        var Count = 0,
            FieldDivID = $(this).parents().parents().attr('id'),
            FieldName = FieldDivID,
            NamefinderExpression = /^(.*)Div$/,
            NumberOfFiles,
            ID = this.id,
            Expression = /.*(\d+)$/,
            IDPlusOne,
            UploadField;

        FieldName = FieldName.replace(NamefinderExpression, "$1");
        $('#' + FieldDivID).children("div").each(function(){
            Count++;
        });
        // get the ID of our clicked field
        NumberOfFiles = $('#' + FieldName + 'NumberOfFiles').attr("value");
        ID = ID.replace(Expression, "$1");

        // if we have reached the amount of configured files
        // we got nothing to do (fields start at 0)
        if(Count == NumberOfFiles){
            return false;
        }

        IDPlusOne = ID;
        IDPlusOne++;
        // if the actual field has a value
        // and it was not the last field
        // we are dealing with a change of the field
        // so we return
        if(this.value && this.type !== 'hidden' && IDPlusOne !== Count){
             return false;
        }

        // append a new upload field including a delete button
        UploadField = '<div id="' + FieldName + '_div' + Count + '"><input id="' + FieldName + Count + '" type="file" size="40" name="' + FieldName + Count + '" /><button id="Delete' + FieldName + Count + '" class="CallForAction SpacingLeft DeleteDynamicFieldAttachment" type="Button" value="' + Core.Language.Translate('Delete') + '"><span>' + Core.Language.Translate('Delete') + '</span></button></div>';
        $('#' + FieldDivID).append(UploadField);

        // bind the upload field to AddFile function
        $(document).off('change', '#' + FieldName + Count);
        $(document).on('change', '#' + FieldName + Count, Core.Agent.DynamicField.Attachment.AddField);

        // bind the delete field to DeleteField function
        $(document).off('click', '#Delete' + FieldName + Count);
        $(document).on('click', '#Delete' + FieldName + Count, Core.Agent.DynamicField.Attachment.DeleteField);
        return false;
    };

    TargetNS.DeleteField = function(){
        var FieldDivID = $(this).parents('div').parents('div').attr('id'),
            FieldName,
            NamefinderExpression = /^(.*)Div$/,
            NumberOfFiles,
            ID,
            Expression,
            Count = 0,
            UploadFieldCount = 0,
            NewID,
            OldID,
            LastID;

        FieldName = $('#' + FieldDivID).attr("id");
        FieldName = FieldName.replace(NamefinderExpression, "$1");

        NumberOfFiles = $('#' + FieldName + 'NumberOfFiles').attr("value");
        // get the number of the pressed delete button
        ID = this.id;
        Expression = /.*(\d+)$/;
        ID = ID.replace(Expression, "$1");

        // find all upload fields
        $('#' + FieldDivID).children("div").each(function(){
            Count++;
        });

        $('#' + FieldDivID).find('input[type=file]').each(function(){
            UploadFieldCount++;
        });
        // If we have just one file input row, delete the content and return
        if(UploadFieldCount === 1 && (parseFloat(ID) + 1) === Count){
            $('#' + FieldName + ID).attr({
                value: ''
            });
            return false;
        }
        // for renaming we need the current ID as NewID
        NewID = ID;
        // and the ID of the next field
        OldID = NewID;
        OldID++;
        // we delete the old field
        $('#' + FieldName + ID).parent().remove();
        // if we didn't delete the last field
        if(OldID < Count){
            // loop through all fields starting from the
            // next existing field
            for (; OldID < Count; NewID++, OldID++){
                // move up the parent div to the place of the deleted fields div
                // change the id
                $('#' + FieldName + '_div' + OldID).attr({
                    id: FieldName + '_div' + NewID
                });
                // move it up to the place of the deleted field:
                // at first remove the binding
                // then change the id and name
                // and finally add the binding to the field again
                $(document).off('change', '#' + FieldName + OldID);
                $('#' + FieldName + OldID).attr({
                    id: FieldName + NewID,
                    name: FieldName + NewID
                    });
                 $(document).on('change', '#' + FieldName + NewID, Core.Agent.DynamicField.Attachment.AddField);
                // same with the delete buttons
                $(document).off('click', '#Delete' + FieldName + OldID);
                $('#Delete' + FieldName + OldID).attr({
                    id: 'Delete' + FieldName + NewID,
                    name: 'Delete' + FieldName + NewID
                    });
                $(document).on('click', '#Delete' + FieldName + NewID, Core.Agent.DynamicField.Attachment.DeleteField);
            }

        }
        // get the ID of the last upload field
        LastID = NewID;
        LastID--;
        // if the last field has a value and we are not at the maximum
        // of allowed fields, we add a new field by triggering the
        // 'change' event on the last field e.g. calling "AddField"
        if($('#' + FieldName + LastID).val().length > 0 && NewID < NumberOfFiles){
            $('#' + FieldName + LastID).trigger('change');
        }
        return false;
    };

    TargetNS.DisableField = function(){
        var FieldName = $(this).attr('id'),
            NamefinderExpression = /^Disable(.*)$/;
        FieldName = FieldName.replace(NamefinderExpression, "$1");

        if(!$('#' + FieldName + 'Transferred').data('OriginalValue')){
            $('#' + FieldName + 'Transferred').data('OriginalValue', $('#' + FieldName + 'Transferred').val());
        }

        if($('#' + FieldName + 'Disabled').val() === '1'){
            $('#' + FieldName + 'Disabled').val('0');
            $('#' + FieldName + 'Transferred').val($('#' + FieldName + 'Transferred').data('OriginalValue'));
            $(this).find('span').val('Disabled');

            $(this).parent().removeAttr('style');
            $(this).parent().attr('style', 'color: black;');
            $(this).parent().removeClass('Disabled');
            $(this).parent().removeClass('DisabledNew');
        }
        else {
            $('#' + FieldName + 'Disabled').val('1');
            $('#' + FieldName + 'Transferred').val('0');

            $(this).find('span').val('Active');

            $(this).parent().removeAttr('style');
            $(this).parent().attr('style', 'color: lightgray;');
            $(this).parent().addClass('Disabled');
            $(this).parent().addClass('DisabledNew');
        }

        Core.Agent.DynamicField.Attachment.CheckDisabledFields();

        return false;
    };

    TargetNS.CheckDisabledFields = function(){
        var ChangedFiles = [],
            Value,
            DialogHeadlineText = Core.Language.Translate('Disable Attachments'),
            CancelText = Core.Language.Translate('Cancel'),
            DisableText = Core.Language.Translate('Disable');

        if(!$('.DisableDynamicFieldAttachment').closest('form').data('WatchDynamicFieldAttachments')){
            $('.DisableDynamicFieldAttachment').closest('form').data('WatchDynamicFieldAttachments', true);

            Core.Form.Validate.SetSubmitFunction($('.DisableDynamicFieldAttachment').closest('form'), function(){

                if($('.DisabledNew')[0]){

                    $('.DisabledNew').each(function(){
                        Value = $.trim($(this).text());
                        ChangedFiles.push(Value);
                    });

                    Core.UI.Dialog.ShowContentDialog($('#DynamicFieldAttachmentDisableConfirmDialog'), DialogHeadlineText, '150px', 'Center', true, [
                        {
                            Label: CancelText,
                            Function: function(){
                                Core.UI.Dialog.CloseDialog($('.Dialog:visible'));
                                Core.Form.EnableForm($('.DisableDynamicFieldAttachment').closest('form'));
                            },
                            Class: 'Primary'
                        },
                        {
                            Label: DisableText,
                            Function: function(){
                                // Set confirmation value
                                $('#Confirmed').val(1);
                                // show waiting animation within dialog
                                $('.Dialog:visible')
                                    .find('.ContentFooter')
                                    .empty()
                                    .end()
                                    .find('.InnerContent .Center')
                                    .width($('.Dialog:visible').find('.InnerContent .Center').width())
                                    .empty()
                                    .append('<span class="AJAXLoader"></span>');
                                // the form was disabled in background already, now enable it again to allow the submit
                                Core.Form.EnableForm($('.DisableDynamicFieldAttachment').closest('form'));
                                // submit form (includes disabling form after submit to prevent multiple submits)
                                $('.DisableDynamicFieldAttachment').closest('form').get(0).submit();
                            }
                        }
                    ]);
                    return false;
                }
                $('.DisableDynamicFieldAttachment').closest('form').get(0).submit();
            });
        }
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;
}(Core.Agent.TicketAction || {}));
