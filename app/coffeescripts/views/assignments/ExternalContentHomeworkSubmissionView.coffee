#
# Copyright (C) 2014 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

import $ from 'jquery'
import Backbone from 'Backbone'
import {verifyPledgeIsChecked} from '../../../../public/javascripts/submit_assignment_helper'

export default class ExternalContentHomeworkSubmissionView extends Backbone.View
  @optionProperty 'externalTool'

  events:
    'click .relaunch-tool': '_relaunchTool'
    'click .submit_button': '_triggerSubmit'
    'click .cancel_button': '_triggerCancel'

  _relaunchTool: (event) =>
    event.preventDefault()
    event.stopPropagation()
    @trigger 'relaunchTool', @externalTool, @model

  _triggerCancel: (event) =>
    event.preventDefault()
    event.stopPropagation()
    @trigger 'cancel', @externalTool, @model

  _triggerSubmit: (event) =>
    event.preventDefault()
    event.stopPropagation()
    @model.set('comment', @$el.find('.submission_comment').val())
    if verifyPledgeIsChecked($('input.turnitin_pledge.external-tool'))
      @submitHomework()
