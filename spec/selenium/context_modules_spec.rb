﻿require File.expand_path(File.dirname(__FILE__) + '/helpers/context_modules_common')

describe "context modules" do
  include_examples "in-process server selenium tests"
  context "as a teacher", :priority => "1" do
    before(:each) do
      course_with_teacher_logged_in
      #have to add quiz and assignment to be able to add them to a new module
      @quiz = @course.assignments.create!(:title => 'quiz assignment', :submission_types => 'online_quiz')
      @assignment = @course.assignments.create!(:title => 'assignment 1', :submission_types => 'online_text_entry')
      @assignment2 = @course.assignments.create!(:title => 'assignment 2',
                                                 :submission_types => 'online_text_entry',
                                                 :due_at => 2.days.from_now,
                                                 :points_possible => 10)
      @assignment3 = @course.assignments.create!(:title => 'assignment 3', :submission_types => 'online_text_entry')

      @ag1 = @course.assignment_groups.create!(:name => "Assignment Group 1")
      @ag2 = @course.assignment_groups.create!(:name => "Assignment Group 2")

      @course.reload
    end

    it "should rearrange child objects in same module" do
      modules = create_modules(1, true)
      #attach 1 assignment to module 1 and 2 assignments to module 2 and add completion reqs
      item1 = modules[0].add_item({:id => @assignment.id, :type => 'assignment'})
      item2 = modules[0].add_item({:id => @assignment2.id, :type => 'assignment'})
      get "/courses/#{@course.id}/modules"
      wait_for_modules_ui
      #setting gui drag icons to pass to driver.action.drag_and_drop
      selector1 = "#context_module_item_#{item1.id} .move_item_link"
      selector2 = "#context_module_item_#{item2.id} .move_item_link"
      list_prior_drag = ff("a.title").map(&:text)
      #performs the change position
      js_drag_and_drop(selector2, selector1)
      wait_for_ajaximations
      list_post_drag = ff("a.title").map(&:text)
      keep_trying_until do
        expect(list_prior_drag[0]).to eq list_post_drag[1]
        expect(list_prior_drag[1]).to eq list_post_drag[0]
      end
    end

    it "should rearrange child object to new module" do
      modules = create_modules(2, true)
      #attach 1 assignment to module 1 and 2 assignments to module 2 and add completion reqs
      item1_mod1 = modules[0].add_item({:id => @assignment.id, :type => 'assignment'})
      item1_mod2 = modules[1].add_item({:id => @assignment2.id, :type => 'assignment'})
      get "/courses/#{@course.id}/modules"
      wait_for_modules_ui
      #setting gui drag icons to pass to driver.action.drag_and_drop
      selector1 = "#context_module_item_#{item1_mod1.id} .move_item_link"
      selector2 = "#context_module_item_#{item1_mod2.id} .move_item_link"
      #performs the change position
      js_drag_and_drop(selector2, selector1)
      wait_for_ajaximations
      list_post_drag = ff("a.title").map(&:text)
      #validates the module 1 assignments are in the expected places and that module 2 context_module_items isn't present
      keep_trying_until do
        expect(list_post_drag[0]).to eq "assignment 2"
        expect(list_post_drag[1]).to eq "assignment 1"
        expect(fj('#context_modules .context_module:last-child .context_module_items .context_module_item')).to be_nil
      end
    end

    it "should only display out-of on an assignment min score restriction when the assignment has a total" do
      ag = @course.assignment_groups.create!
      a1 = ag.assignments.create!(:context => @course)
      a1.points_possible = 10
      a1.save
      a2 = ag.assignments.create!(:context => @course)
      m = @course.context_modules.create!

      make_content_tag = lambda do |assignment|
        ct = ContentTag.new
        ct.content_id = assignment.id
        ct.content_type = 'Assignment'
        ct.context_id = @course.id
        ct.context_type = 'Course'
        ct.title = "Assignment #{assignment.id}"
        ct.tag_type = "context_module"
        ct.context_module_id = m.id
        ct.context_code = "course_#{@course.id}"
        ct.save!
        ct
      end
      content_tag_1 = make_content_tag.call a1
      content_tag_2 = make_content_tag.call a2

      get "/courses/#{@course.id}/modules"

      keep_trying_until do
        f('.ig-header-admin  .al-trigger').click
        hover_and_click('#context_modules .edit_module_link')
        wait_for_ajax_requests
        expect(f('#add_context_module_form')).to be_displayed
      end
      assignment_picker = keep_trying_until do
        f('.add_completion_criterion_link').click
        fj('.assignment_picker:visible')
      end

      assignment_picker.find_element(:css, "option[value='#{content_tag_1.id}']").click
      requirement_picker = fj('.assignment_requirement_picker:visible')
      requirement_picker.find_element(:css, 'option[value="min_score"]').click
      expect(driver.execute_script('return $(".points_possible_parent:visible").length')).to be > 0

      assignment_picker.find_element(:css, "option[value='#{content_tag_2.id}']").click
      requirement_picker.find_element(:css, 'option[value="min_score"]').click
      expect(driver.execute_script('return $(".points_possible_parent:visible").length')).to eq 0
    end

    it "should add and remove completion criteria" do
      get "/courses/#{@course.id}/modules"
      add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)

      @course.reload
      smodule = @course.context_modules.first
      smodule.publish!
      # add completion criterion
      f('.ig-header-admin .al-trigger').click
      wait_for_ajaximations
      f('.edit_module_link').click
      wait_for_ajaximations
      edit_form = f('#add_context_module_form')
      expect(edit_form).to be_displayed
      f('.add_completion_criterion_link', edit_form).click
      wait_for_ajaximations
      click_option('#add_context_module_form .assignment_picker', @assignment.title, :text)
      click_option('#add_context_module_form .assignment_requirement_picker', 'must_submit', :value)

      submit_form(edit_form)
      expect(edit_form).not_to be_displayed
      # should show relock warning since we're adding a completion requirement to an active module
      test_relock

      # verify it was added
      smodule.reload
      expect(smodule).not_to be_nil
      expect(smodule.completion_requirements).not_to be_empty
      expect(smodule.completion_requirements[0][:type]).to eq 'must_submit'

      # delete the criterion, then cancel the form
      f('.ig-header-admin .al-trigger').click
      wait_for_ajaximations
      f('.edit_module_link').click
      wait_for_ajaximations
      edit_form = f('#add_context_module_form')
      expect(edit_form).to be_displayed
      f('.completion_entry .delete_criterion_link', edit_form).click
      wait_for_ajaximations
      ff('.cancel_button.ui-button', dialog_for(edit_form)).last.click
      wait_for_ajaximations

      # now delete the criterion frd
      # (if the previous step did even though it shouldn't have, this will error)
      f('.ig-header-admin .al-trigger').click
      wait_for_ajaximations
      f('.edit_module_link').click
      wait_for_ajaximations
      edit_form = f('#add_context_module_form')
      expect(edit_form).to be_displayed
      f('.completion_entry .delete_criterion_link', edit_form).click
      wait_for_ajaximations
      submit_form(edit_form)
      wait_for_ajax_requests

      # verify it's gone
      @course.reload
      expect(@course.context_modules.first.completion_requirements).to eq []

      # and also make sure the form remembers that it's gone (#8329)
      f('.ig-header-admin .al-trigger').click
      f('.edit_module_link').click
      edit_form = f('#add_context_module_form')
      expect(edit_form).to be_displayed
      expect(ff('.completion_entry .delete_criterion_link', edit_form)).to be_empty
    end

    it "should delete a module item" do
      get "/courses/#{@course.id}/modules"

      add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      f('.context_module_item .al-trigger').click()
      wait_for_ajaximations
      f('.delete_item_link').click
      expect(driver.switch_to.alert).not_to be_nil
      driver.switch_to.alert.accept
      wait_for_ajaximations
      keep_trying_until do
        expect(f('.context_module_items')).not_to include_text(@assignment.title)
        true
      end
    end

    it "should edit a module item and validate the changes stick" do
      get "/courses/#{@course.id}/modules"

      item_edit_text = "Assignment Edit 1"
      module_item = add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      tag = ContentTag.last
      edit_module_item(module_item) do |edit_form|
        replace_content(edit_form.find_element(:id, 'content_tag_title'), item_edit_text)
      end
      module_item = f("#context_module_item_#{tag.id}")
      expect(module_item).to include_text(item_edit_text)

      get "/courses/#{@course.id}/assignments/#{@assignment.id}"
      expect(f('h1.title').text).to eq item_edit_text

      expect_new_page_load { f('.modules').click }
      expect(f("#context_module_item_#{tag.id} .title").text).to eq item_edit_text
    end

    it "should rename all instances of an item" do
      get "/courses/#{@course.id}/modules"

      add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      item2 = add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      edit_module_item(item2) do |edit_form|
        replace_content(edit_form.find_element(:id, 'content_tag_title'), "renamed assignment")
      end
      all_items = ff(".context_module_item.Assignment_#{@assignment.id}")
      expect(all_items.size).to eq 2
      all_items.each { |i| expect(i.find_element(:css, '.title').text).to eq 'renamed assignment' }
      expect(@assignment.reload.title).to eq 'renamed assignment'
      run_jobs
      @assignment.context_module_tags.each { |tag| expect(tag.title).to eq 'renamed assignment' }

      # reload the page and renaming should still work on existing items
      get "/courses/#{@course.id}/modules"
      item3 = add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      edit_module_item(item3) do |edit_form|
        replace_content(edit_form.find_element(:id, 'content_tag_title'), "again")
      end
      all_items = ff(".context_module_item.Assignment_#{@assignment.id}")
      expect(all_items.size).to eq 3
      all_items.each { |i| expect(i.find_element(:css, '.title').text).to eq 'again' }
      expect(@assignment.reload.title).to eq 'again'
      run_jobs
      @assignment.context_module_tags.each { |tag| expect(tag.title).to eq 'again' }
    end

    it "should not create a duplicate page if you publish after renaming" do
      mod = @course.context_modules.create! name: 'TestModule'
      page = @course.wiki.wiki_pages.create title: 'A Page'
      page.workflow_state = 'unpublished'
      page.save!
      page_count = @course.wiki.wiki_pages.count
      tag = mod.add_item({:id => page.id, :type => 'wiki_page'})

      get "/courses/#{@course.id}/modules"
      wait_for_modules_ui

      item = f("#context_module_item_#{tag.id}")
      edit_module_item(item) do |edit_form|
        replace_content(edit_form.find_element(:id, 'content_tag_title'), 'Renamed!')
      end

      item = f("#context_module_item_#{tag.id}")
      item.find_element(:css, '.publish-icon').click
      wait_for_ajax_requests

      expect(@course.wiki.wiki_pages.count).to eq page_count
      expect(page.reload).to be_published
    end

    it "should add the 'with-completion-requirements' class to rows that have requirements" do
      mod = @course.context_modules.create! name: 'TestModule'
      tag = mod.add_item({:id => @assignment.id, :type => 'assignment'})

      mod.completion_requirements = {tag.id => {:type => 'must_view'}}
      mod.save

      get "/courses/#{@course.id}/modules"

      ig_rows = ff("#context_module_item_#{tag.id} .with-completion-requirements")
      expect(ig_rows).not_to be_empty
    end

    it "should add a title attribute to the text header" do
      text_header = 'This is a really long module text header that should be truncated to exactly 98 characters plus the ... part so 101 characters really'
      mod = @course.context_modules.create! name: 'TestModule'
      tag1 = mod.add_item(title: text_header, type: 'sub_header')

      get "/courses/#{@course.id}/modules"
      locked_title = ff("#context_module_item_#{tag1.id} .locked_title[title]")

      expect(locked_title[0].attribute(:title)).to eq text_header
    end

    it "should not rename every text header when you rename one" do
      mod = @course.context_modules.create! name: 'TestModule'
      tag1 = mod.add_item(title: 'First text header', type: 'sub_header')
      tag2 = mod.add_item(title: 'Second text header', type: 'sub_header')

      get "/courses/#{@course.id}/modules"
      wait_for_modules_ui
      item2 = f("#context_module_item_#{tag2.id}")
      edit_module_item(item2) do |edit_form|
        replace_content(edit_form.find_element(:id, 'content_tag_title'), 'Renamed!')
      end

      item1 = f("#context_module_item_#{tag1.id}")
      expect(item1).not_to include_text('Renamed!')
    end

    it "should not rename every external tool link when you rename one" do
      tool = @course.context_external_tools.create! name: 'WHAT', consumer_key: 'what', shared_secret: 'what', url: 'http://what.example.org'
      mod = @course.context_modules.create! name: 'TestModule'
      tag1 = mod.add_item(title: 'A', type: 'external_tool', id: tool.id, url: 'http://what.example.org/A')
      tag2 = mod.add_item(title: 'B', type: 'external_tool', id: tool.id, url: 'http://what.example.org/B')

      get "/courses/#{@course.id}/modules"
      wait_for_modules_ui
      item2 = f("#context_module_item_#{tag2.id}")
      edit_module_item(item2) do |edit_form|
        replace_content(edit_form.find_element(:id, 'content_tag_title'), 'Renamed!')
      end

      item1 = f("#context_module_item_#{tag1.id}")
      expect(item1).not_to include_text('Renamed!')
    end

    it "should add a new quiz to a module in a specific assignment group" do
      get "/courses/#{@course.id}/modules"

      add_new_module_item('#quizs_select', 'Quiz', '[ New Quiz ]', "New Quiz") do
        click_option("select[name='quiz[assignment_group_id]']", @ag2.name)
      end
      expect(@ag2.assignments.length).to eq 1
      expect(@ag2.assignments.first.title).to eq "New Quiz"
    end

    it "should add a text header to a module" do
      get "/courses/#{@course.id}/modules"

      header_text = 'new header text'
      add_module('Text Header Module')
      f('.ig-header-admin .al-trigger').click
      f('.add_module_item_link').click
      select_module_item('#add_module_item_select', 'Text Header')
      keep_trying_until do
        replace_content(f('#sub_header_title'), header_text)
        true
      end
      fj('.add_item_button.ui-button').click
      wait_for_ajaximations
      tag = ContentTag.last
      module_item = f("#context_module_item_#{tag.id}")
      expect(module_item).to include_text(header_text)
    end

    it "should hide module contents" do
      get "/courses/#{@course.id}/modules"

      add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      f('.collapse_module_link').click
      wait_for_ajaximations
      expect(f('.context_module .content')).not_to be_displayed
    end

    it "should allow adding an item twice" do
      get "/courses/#{@course.id}/modules"
      tag = add_new_external_item('External Tool', 'www.instructure.com', 'Instructure')
      expect(driver.execute_script("return $('#context_module_item_#{tag.id} .type').text()")).to eq "context_external_tool"

      item1 = add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      item2 = add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      expect(item1).not_to eq item2
      expect(@assignment.reload.context_module_tags.size).to eq 2
    end

    it "should not save an invalid external tool" do
      get "/courses/#{@course.id}/modules"

      add_module 'Test module'
      f('.ig-header-admin .al-trigger').click
      wait_for_ajaximations
      f('.add_module_item_link').click
      wait_for_ajaximations
      keep_trying_until do
        select_module_item('#add_module_item_select', 'External Tool')
        fj('.add_item_button.ui-button').click
        expect(ff('.alert.alert-error').length).to eq 1
      end
      expect(fj('.alert.alert-error:visible').text).to eq "An external tool can't be saved without a URL."
    end

    it "should add 2 modules with the first one as a prerequisite" do
      get "/courses/#{@course.id}/modules"

      first_module_name = 'First Module'
      second_module_name = 'Second Module'
      add_module(first_module_name)
      #adding second module - can't use add_module method because a prerequisite needs to be added to this module
      add_form = new_module_form
      replace_content(add_form.find_element(:id, 'context_module_name'), second_module_name)
      f('.ui-dialog .add_prerequisite_link').click
      wait_for_ajaximations
      #have to do it this way because the select has no css attributes on it
      click_option('.criterion select', "the module, #{first_module_name}")
      submit_form(add_form)
      wait_for_ajaximations
      mod1 = @course.context_modules.where(:name => first_module_name).first
      mod2 = @course.context_modules.where(:name => second_module_name).first
      context_module = f("#context_module_#{mod2.id}")
      driver.action.move_to(context_module).perform
      f("#context_module_#{mod2.id} .ig-header-admin .al-trigger").click
      f("#context_module_#{mod2.id} .edit_module_link").click
      expect(add_form).to be_displayed
      wait_for_ajaximations
      prereq_select = fj('.criterion select')
      option = first_selected_option(prereq_select)
      expect(option.text).to eq 'the module, ' + first_module_name

      ff('.cancel_button.ui-button', dialog_for(add_form)).last.click
      wait_for_ajaximations
      mod2.publish!

      # should bring up relock dialog on publish
      f("#context_module_#{mod1.id} .publish-icon").click
      test_relock
    end

    it "should rearrange modules" do
      m1 = @course.context_modules.create!(:name => 'module 1')
      m2 = @course.context_modules.create!(:name => 'module 2')

      get "/courses/#{@course.id}/modules"
      sleep 2 #not sure what we are waiting on but drag and drop will not work, unless we wait

      m1_a = fj('#context_modules .context_module:first-child .reorder_module_link a')
      m2_a = fj('#context_modules .context_module:last-child .reorder_module_link a')
      driver.action.drag_and_drop(m2_a, m1_a).perform
      wait_for_ajax_requests

      m1.reload
      expect(m1.position).to eq 2
      m2.reload
      expect(m2.position).to eq 1
    end

    it "should validate locking a module item display functionality" do
      get "/courses/#{@course.id}/modules"

      add_form = new_module_form
      lock_check = add_form.find_element(:id, 'unlock_module_at')
      lock_check.click
      wait_for_ajaximations
      expect(add_form.find_element(:css, 'tr.unlock_module_at_details')).to be_displayed
      lock_check.click
      wait_for_ajaximations
      expect(add_form.find_element(:css, 'tr.unlock_module_at_details')).not_to be_displayed
    end

    it "should prompt relock when adding an unlock_at date" do
      mod = @course.context_modules.create!(:name => "name")

      get "/courses/#{@course.id}/modules"

      keep_trying_until do
        f(".ig-header-admin .al-trigger").click
        f(".edit_module_link").click
        expect(f('#add_context_module_form')).to be_displayed
      end
      edit_form = f('#add_context_module_form')

      lock_check = edit_form.find_element(:id, 'unlock_module_at')
      lock_check.click
      wait_for_ajaximations
      unlock_date = edit_form.find_element(:id, 'context_module_unlock_at')
      unlock_date.send_keys((Date.today + 2.days).to_s)
      wait_for_ajaximations
      submit_form(edit_form)
      expect(edit_form).not_to be_displayed
      test_relock
    end

    it "should properly change indent of an item with arrows" do
      get "/courses/#{@course.id}/modules"

      add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      tag = ContentTag.last

      driver.execute_script("$('#context_module_item_#{tag.id} .indent_item_link').hover().click()")
      wait_for_ajaximations
      expect(f("#context_module_item_#{tag.id}")).to have_class('indent_1')

      tag.reload
      expect(tag.indent).to eq 1
    end

    it "should properly change indent of an item from edit dialog" do
      get "/courses/#{@course.id}/modules"

      add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
      tag = ContentTag.last

      driver.execute_script("$('#context_module_item_#{tag.id} .edit_item_link').hover().click()")
      click_option("#content_tag_indent_select", "Indent 1 Level")
      submit_form("#edit_item_form")
      wait_for_ajaximations
      expect(f("#context_module_item_#{tag.id}")).to have_class('indent_1')

      tag.reload
      expect(tag.indent).to eq 1
    end

    context "module item cog focus management", :priority => "1" do

      before :each do
        get "/courses/#{@course.id}/modules"
        add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
        @tag = ContentTag.last
        f("#context_module_item_#{@tag.id} .al-trigger").click
      end

      it "should return focus to the cog menu when closing the edit dialog for an item" do
        hover_and_click("#context_module_item_#{@tag.id} .edit_item_link")
        keep_trying_until { ff('.cancel_button.ui-button')[2] }.click
        check_element_has_focus(fj("#context_module_item_#{@tag.id} .al-trigger"))
      end

      it "should return focus to the module item cog when indenting" do
        hover_and_click("#context_module_item_#{@tag.id} .indent_item_link")
        wait_for_ajaximations
        check_element_has_focus(fj("#context_module_item_#{@tag.id} .al-trigger"))
      end

      it "should return focus to the module item cog when outdenting" do
        hover_and_click("#context_module_item_#{@tag.id} .indent_item_link")
        f("#context_module_item_#{@tag.id} .al-trigger").click
        hover_and_click("#context_module_item_#{@tag.id} .outdent_item_link")
        wait_for_ajaximations
        check_element_has_focus(fj("#context_module_item_#{@tag.id} .al-trigger"))
      end

      it "should return focus to the module item cog when closing the move dialog" do
        hover_and_click("#context_module_item_#{@tag.id} .move_module_item_link")
        f('#move_module_item_cancel_btn').click
        check_element_has_focus(fj("#context_module_item_#{@tag.id} .al-trigger"))
      end

      it "should return focus to the module item cog when cancelling a delete" do
        hover_and_click("#context_module_item_#{@tag.id} .delete_item_link")
        expect(driver.switch_to.alert).not_to be_nil
        driver.switch_to.alert.dismiss
        wait_for_ajaximations
        check_element_has_focus(fj("#context_module_item_#{@tag.id} .al-trigger"))
      end

      it "should return focus to the previous module item cog when deleting a module item." do
        add_existing_module_item('#assignments_select', 'Assignment', @assignment.title)
        @tag2 = ContentTag.last
        hover_and_click("#context_module_item_#{@tag2.id} .delete_item_link")
        expect(driver.switch_to.alert).not_to be_nil
        driver.switch_to.alert.accept
        wait_for_ajaximations
        check_element_has_focus(fj("#context_module_item_#{@tag.id} .al-trigger"))
      end

      it "should return focus to the parent module's cog when deleting the last module item." do
        hover_and_click("#context_module_item_#{@tag.id} .delete_item_link")
        expect(driver.switch_to.alert).not_to be_nil
        driver.switch_to.alert.accept
        wait_for_ajaximations
        check_element_has_focus(f("#context_module_#{@tag.context_module_id} .al-trigger"))
      end
    end


    it "should still display due date and points possible after indent change" do
      get "/courses/#{@course.id}/modules"

      module_item = add_existing_module_item('#assignments_select', 'Assignment', @assignment2.title)
      tag = ContentTag.last

      expect(module_item.find_element(:css, ".due_date_display").text).not_to be_blank
      expect(module_item.find_element(:css, ".points_possible_display")).to include_text "10"

      # change indent with arrows
      driver.execute_script("$('#context_module_item_#{tag.id} .indent_item_link').hover().click()")
      wait_for_ajaximations

      module_item = f("#context_module_item_#{tag.id}")
      expect(module_item.find_element(:css, ".due_date_display").text).not_to be_blank
      expect(module_item.find_element(:css, ".points_possible_display")).to include_text "10"

      # change indent from edit form
      driver.execute_script("$('#context_module_item_#{tag.id} .edit_item_link').hover().click()")
      click_option("#content_tag_indent_select", "Don't Indent")
      submit_form("#edit_item_form")
      wait_for_ajaximations

      module_item = f("#context_module_item_#{tag.id}")
      expect(module_item.find_element(:css, ".due_date_display").text).not_to be_blank
      expect(module_item.find_element(:css, ".points_possible_display")).to include_text "10"
    end

    context "Keyboard Accessibility", :priority => "1" do
      it "should set focus to the first drag handle after the + Module button" do
        # Add two modules, so the drag handles show up.
        course_module
        course_module
        get "/courses/#{@course.id}/modules"

        driver.execute_script("$('.add_module_link').focus()")
        add_module_link = f('.add_module_link')
        add_module_link.send_keys("\t")
        first_handle = f('.icon-drag-handle')
        check_element_has_focus(first_handle)

      end

      it "should use the keyboard shortcuts to navigate through modules and module items" do
        # Test these shortcuts (access menu by pressing comma key):
        # Up : Previous Module/Item
        # Down : Next Module/Item
        # Space : Move Module/Item
        # k : Previous Module/Item
        # j : Next Module/Item
        # e : Edit Module/Item
        # d : Delete Current Module/Item
        # i : Increase Indent
        # o : Decrease Indent
        # n : New Module
        
        modules = create_modules(2, true)
        modules[0].add_item({:id => @assignment.id, :type => 'assignment'})
        modules[0].add_item({:id => @assignment2.id, :type => 'assignment'})
        modules[1].add_item({:id => @assignment3.id, :type => 'assignment'})
        get "/courses/#{@course.id}/modules"
        
        context_modules = ff('.context_module .icon-drag-handle')
        context_module_items = ff('.context_module_item a.title')

        # Navigate through modules and module items
        f('html').send_keys("j")
        check_element_has_focus(context_modules[0])

        context_modules[0].send_keys(:arrow_down)
        check_element_has_focus(context_module_items[0])
        
        context_module_items[0].send_keys("j")
        check_element_has_focus(context_module_items[1])

        context_module_items[1].send_keys("k")
        check_element_has_focus(context_module_items[0])

        context_module_items[0].send_keys(:arrow_up)
        check_element_has_focus(context_modules[0])
        
        # Test Edit key
        wait_for_ajaximations(1000) # Has to wait one second before sending keys for it to work
        context_modules[0].send_keys("e")
        expect(f('#add_context_module_form')).to be_displayed
        ff('.cancel_button', dialog_for(f('#add_context_module_form'))).last.click

        # Test New Module key
        wait_for_ajaximations(1000)
        context_modules[0].send_keys("n")
        expect(f('#add_context_module_form')).to be_displayed
        ff('.cancel_button', dialog_for(f('#add_context_module_form'))).last.click

        context_modules[0].send_keys(:arrow_down)
        check_element_has_focus(context_module_items[0])

        # Test Indent / Outdent
        expect(ff('.context_module_item')[0]).to have_class('indent_0')

        wait_for_ajaximations(1000) 
        context_module_items[0].send_keys("i")
        keep_trying_until do
          expect(ff('.context_module_item')[0]).to have_class('indent_1')
        end
        
        wait_for_ajaximations(1000)
        ff('.context_module_item a.title')[0].send_keys("o")
        keep_trying_until do
          expect(ff('.context_module_item')[0]).to have_class('indent_0')
        end

        # Test Delete key
        wait_for_ajaximations(1000)
        new_first_module_item = ff('.context_module_item')[1]
        ff('.context_module_item')[0].send_keys("d")
        driver.switch_to.alert.accept
        keep_trying_until do
          expect(ff('.context_module_item')[0]).to eq(new_first_module_item)
        end

      end
    end

    context "multiple overridden due dates", :priority => "2" do
      def create_section_override(section, due_at)
        override = assignment_override_model(:assignment => @assignment)
        override.set = section
        override.override_due_at(due_at)
        override.save!
      end

      it "should indicate when course sections have multiple due dates" do
        modules = create_modules(1, true)
        modules[0].add_item({:id => @assignment.id, :type => 'assignment'})

        cs1 = @course.default_section
        cs2 = @course.course_sections.create!

        create_section_override(cs1, 3.days.from_now)
        create_section_override(cs2, 4.days.from_now)

        get "/courses/#{@course.id}/modules"

        expect(f(".due_date_display").text).to eq "Multiple Due Dates"
      end

      it "should not indicate multiple due dates if the sections' dates are the same" do
        skip("needs to ignore base if all visible sections are overridden")
        modules = create_modules(1, true)
        modules[0].add_item({:id => @assignment.id, :type => 'assignment'})

        cs1 = @course.default_section
        cs2 = @course.course_sections.create!

        due_at = 3.days.from_now
        create_section_override(cs1, due_at)
        create_section_override(cs2, due_at)

        get "/courses/#{@course.id}/modules"


        expect(f(".due_date_display").text).not_to be_blank
        expect(f(".due_date_display").text).not_to eq "Multiple Due Dates"
      end

      it "should use assignment due date if there is no section override" do
        modules = create_modules(1, true)
        modules[0].add_item({:id => @assignment.id, :type => 'assignment'})

        cs1 = @course.default_section
        cs2 = @course.course_sections.create!

        due_at = 3.days.from_now
        create_section_override(cs1, due_at)
        @assignment.due_at = due_at
        @assignment.save!

        get "/courses/#{@course.id}/modules"
        expect(f(".due_date_display").text).not_to be_blank
        expect(f(".due_date_display").text).not_to eq "Multiple Due Dates"
      end

      it "should only use the sections the user is restricted to" do
        skip("needs to ignore base if all visible sections are overridden")
        modules = create_modules(1, true)
        modules[0].add_item({:id => @assignment.id, :type => 'assignment'})

        cs1 = @course.default_section
        cs2 = @course.course_sections.create!
        cs3 = @course.course_sections.create!

        user_logged_in
        @course.enroll_user(@user, 'TaEnrollment', :section => cs1, :allow_multiple_enrollments => true, :limit_privileges_to_course_section => true).accept!
        @course.enroll_user(@user, 'TaEnrollment', :section => cs2, :allow_multiple_enrollments => true, :limit_privileges_to_course_section => true).accept!

        due_at = 3.days.from_now
        create_section_override(cs1, due_at)
        create_section_override(cs2, due_at)
        create_section_override(cs3, due_at + 1.day) # This override should not matter

        get "/courses/#{@course.id}/modules"

        expect(f(".due_date_display").text).not_to be_blank
        expect(f(".due_date_display").text).not_to eq "Multiple Due Dates"
      end
    end

    it "should preserve completion criteria after indent change" do
      mod = @course.context_modules.create! name: 'Test Module'
      tag = mod.add_item(type: 'assignment', id: @assignment2.id)
      mod.completion_requirements = {tag.id => {type: 'must_submit'}}
      mod.save!

      get "/courses/#{@course.id}/modules"

      # indent the item
      driver.execute_script("$('#context_module_item_#{tag.id} .indent_item_link').hover().click()")
      wait_for_ajaximations

      # make sure the completion criterion was preserved
      module_item = f("#context_module_item_#{tag.id}")
      expect(module_item.attribute('class').split).to include 'must_submit_requirement'
      expect(f('.criterion', module_item).attribute('class').split).to include 'defined'
      expect(driver.execute_script("return $('#context_module_item_#{tag.id} .criterion_type').text()")).to eq "must_submit"
    end

    it "should show a vdd tooltip summary for assignments with multiple due dates" do
      selector = "li.Assignment_#{@assignment2.id} .due_date_display"
      get "/courses/#{@course.id}/modules"
      add_existing_module_item('#assignments_select', 'Assignment', @assignment2.title)
      wait_for_ajaximations
      expect(f(selector)).not_to include_text "Multiple Due Dates"

      # add a second due date
      new_section = @course.course_sections.create!(:name => 'New Section')
      override = @assignment2.assignment_overrides.build
      override.set = new_section
      override.due_at = Time.zone.now + 1.day
      override.due_at_overridden = true
      override.save!

      get "/courses/#{@course.id}/modules"
      expect(f(selector)).to include_text "Multiple Due Dates"
      driver.mouse.move_to f("#{selector} a")
      wait_for_ajaximations

      tooltip = fj('.vdd_tooltip_content:visible')
      expect(tooltip).to include_text 'New Section'
      expect(tooltip).to include_text 'Everyone else'
    end

    it "should publish a file from the modules page" do
      @module = @course.context_modules.create!(:name => "some module")
      @file = @course.attachments.create!(:display_name => "some file", :uploaded_data => default_uploaded_data, :locked => true)
      @tag = @module.add_item({:id => @file.id, :type => 'attachment'})
      expect(@file.reload).not_to be_published
      get "/courses/#{@course.id}/modules"
      f("[data-id='#{@file.id}'] > button.published-status").click
      ff(".permissions-dialog-form input[name='permissions']")[0].click
      f(".permissions-dialog-form [type='submit']").click
      wait_for_ajaximations
      expect(@file.reload).to be_published
    end

    it "should show the file publish button on course home" do
      @course.default_view = 'modules'
      @course.save!

      @module = @course.context_modules.create!(:name => "some module")
      @file = @course.attachments.create!(:display_name => "some file", :uploaded_data => default_uploaded_data)
      @tag = @module.add_item({:id => @file.id, :type => 'attachment'})

      get "/courses/#{@course.id}"
      expect(f(".context_module_item.attachment .icon-publish")).to be_displayed
    end

    it "should render publish buttons in collapsed modules" do
      @module = @course.context_modules.create! name: "collapsed"
      tag = @module.add_item(type: 'assignment', id: @assignment2.id)
      @progression = @module.evaluate_for(@user)
      @progression.collapsed = true
      @progression.save!
      get "/courses/#{@course.id}/modules"
      wait_for_ajaximations
      f('.expand_module_link').click
      wait_for_ajaximations
      expect(f(".context_module_item.assignment .icon-publish")).to be_displayed
    end
  end

  context "as a teacher", :priority => "1" do
    before(:each) do
      course_with_teacher_logged_in
      @course.default_view = 'modules'
      @course.save!
      get "/courses/#{@course.id}"
    end

    it "should render as course home page" do
      create_modules(1)
      @course.default_view = 'modules'
      @course.save!
      get "/courses/#{@course.id}"
      expect(f('.add_module_link').text).not_to be_nil
    end

    it "publishes an unpublished module" do
      add_module('New Module')
      wait_for_ajaximations
      expect(f('.context_module')).to have_class('unpublished_module')
      expect(@course.context_modules.count).to eq 1
      mod = @course.context_modules.first
      expect(mod.name).to eq 'New Module'
      publish_module
      mod.reload
      expect(mod).to be_published
      expect(f('#context_modules .publish-icon-published')).to be_displayed
    end

    it "unpublishes a published module" do
      add_module('New Module')
      mod = @course.context_modules.first
      publish_module
      mod.reload
      expect(mod).to be_published
      unpublish_module
      mod.reload
      expect(mod).to be_unpublished
    end

    it "should edit a module" do
      edit_text = 'Module Edited'
      add_module('Edit Module')
      f('.ig-header-admin .al-trigger').click
      f('.edit_module_link').click
      expect(f('#add_context_module_form')).to be_displayed
      edit_form = f('#add_context_module_form')
      edit_form.find_element(:id, 'context_module_name').send_keys(edit_text)
      submit_form(edit_form)
      expect(edit_form).not_to be_displayed
      wait_for_ajaximations
      expect(f('.context_module > .header')).to include_text(edit_text)
    end

    it "should delete a module" do
      add_module('Delete Module')
      driver.execute_script("$('.context_module').addClass('context_module_hover')")
      f('.ig-header-admin .al-trigger').click
      wait_for_ajaximations
      f('.delete_module_link').click
      expect(driver.switch_to.alert).not_to be_nil
      driver.switch_to.alert.accept
      wait_for_ajaximations
      refresh_page
      expect(f('#no_context_modules_message')).to be_displayed
      wait_for_ajaximations
      expect(f('.context_module > .header')).not_to be_displayed
    end

    it "should add an assignment to a module" do
      add_new_module_item('#assignments_select', 'Assignment', '[ New Assignment ]', 'New Assignment Title')
      expect(fln('New Assignment Title')).to be_displayed
    end


    it "should add a quiz to a module" do
      add_new_module_item('#quizs_select', 'Quiz', '[ New Quiz ]', 'New Quiz Title')
      verify_persistence('New Quiz Title')
    end

    it "should add a content page item to a module" do
      add_new_module_item('#wiki_pages_select', 'Content Page', '[ New Page ]', 'New Page Title')
      verify_persistence('New Page Title')
    end

    it "should add a discussion item to a module" do
      get "/courses/#{@course.id}/modules"
      add_new_module_item('#discussion_topics_select', 'Discussion', '[ New Topic ]', 'New Discussion Title')
      verify_persistence('New Discussion Title')
    end

    it "should add an external url item to a module" do
      get "/courses/#{@course.id}/modules"
      add_new_external_item('External URL', 'www.google.com', 'Google')
      expect(fln('Google')).to be_displayed
    end

    it "should add an external tool item to a module" do
      get "/courses/#{@course.id}/modules"
      add_new_external_item('External Tool', 'www.instructure.com', 'Instructure')
      expect(fln('Instructure')).to be_displayed
    end
  end

  describe "files" do
    FILE_NAME = 'some test file'

    before(:each) do
      course_with_teacher_logged_in
      #adding file to course
      @file = @course.attachments.create!(:display_name => FILE_NAME, :uploaded_data => default_uploaded_data)
      @file.context = @course
      @file.save!
    end

    it "should add a file item to a module" do
      get "/courses/#{@course.id}/modules"

      add_existing_module_item('#attachments_select', 'File', FILE_NAME)
    end

    it "should not remove the file link in a module when file is overwritten" do
      course_module
      @module.add_item({:id => @file.id, :type => 'attachment'})
      get "/courses/#{@course.id}/modules"

      expect(f('.context_module_item')).to include_text(FILE_NAME)
      file = @course.attachments.create!(:display_name => FILE_NAME, :uploaded_data => default_uploaded_data)
      file.context = @course
      file.save!
      Attachment.last.handle_duplicates(:overwrite)
      refresh_page
      expect(f('.context_module_item')).to include_text(FILE_NAME)
    end
  end

  context "logged out", :priority => "2" do
    before(:each) do
      @course = course(:active_all => true)
      course_module
      @course.is_public = true
      @course.save!
      @course.reload
      remove_user_session
    end

    it "loads page with differentiated assignments on" do
      @course.enable_feature!(:differentiated_assignments)
      assert_page_loads
    end

    it "loads page with differentiated assignments on" do
      @course.disable_feature!(:differentiated_assignments)
      assert_page_loads
    end
  end
end
