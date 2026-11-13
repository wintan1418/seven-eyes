# Saved service orders ("Sunday Service", "Midweek"). JSON for the template
# picker (cached on the device so it opens offline), upsert by the device's id
# so a save made offline replays safely, and "start a new service" — a new
# study whose queue is the template's order. Accounts only (guests get a 401).
class ServiceTemplatesController < ApplicationController
  allow_unauthenticated_access only: %i[ index update destroy start ]
  before_action :require_account

  # GET /service_templates
  def index
    render json: { templates: current_user.service_templates.recent_first.map(&:as_device_json) }
  end

  # PUT /service_templates/:id {service_template: {name, items: […]}}
  def update
    template = ServiceTemplate.save_for!(current_user, params[:id], name: params.dig(:service_template, :name),
                                         items: raw_items)
    render json: template.as_device_json
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # DELETE /service_templates/:id
  def destroy
    current_user.service_templates.find_by(client_id: params[:id].to_s)&.destroy
    head :no_content
  end

  # POST /service_templates/:id/start — a new service from this order.
  def start
    template = current_user.service_templates.find_by!(client_id: params[:id].to_s)
    study = template.start!
    respond_to do |format|
      format.json { render json: { url: study_path(study), id: study.id }, status: :created }
      format.html { redirect_to study_path(study) }
    end
  end

  private

  # Items are free-form JSON (each kind has its own shape); ServiceTemplate
  # keeps only the known fields of known kinds.
  def raw_items
    items = params.dig(:service_template, :items)
    items = items.to_unsafe_h.values if items.respond_to?(:to_unsafe_h)
    Array(items).map { |i| i.respond_to?(:to_unsafe_h) ? i.to_unsafe_h : i }
  end

  def require_account
    head :unauthorized unless authenticated?
  end
end
