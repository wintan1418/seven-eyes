require "test_helper"

class StudiesManagementTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "renaming a study persists the new name" do
    study = users(:one).studies.create!(name: "Untitled Study", pane_count: 2)
    patch study_path(study), params: { study: { name: "Justification — Sept 14" } }
    assert_redirected_to study_path(study)
    assert_equal "Justification — Sept 14", study.reload.name
  end

  test "deleting a study removes it and returns to root" do
    study = users(:one).studies.create!(name: "Scratch", pane_count: 1)
    assert_difference -> { users(:one).studies.count }, -1 do
      delete study_path(study)
    end
    assert_redirected_to root_path
  end

  test "cannot delete another user's study" do
    other = users(:two).studies.create!(name: "Theirs", pane_count: 1)
    delete study_path(other)
    assert_response :not_found
    assert Study.exists?(other.id)
  end

  test "the workspace shows an editable name field and a delete control" do
    study = users(:one).studies.create!(name: "Romans study", pane_count: 1)
    get study_path(study)
    assert_response :success
    assert_select "input.ps-study-name-input[value=?]", "Romans study"
    assert_select "form[action=?]", study_path(study) # delete button form present
  end
end
