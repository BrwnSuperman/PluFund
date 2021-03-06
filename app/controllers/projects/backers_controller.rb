class Projects::BackersController < ApplicationController
  inherit_resources
  actions :index, :show, :new, :update, :review, :create, :credits_checkout
  skip_before_filter :force_http, only: [:create, :edit, :update, :credits_checkout]
  skip_before_filter :verify_authenticity_token, only: [:moip]
  has_scope :available_to_count, type: :boolean
  has_scope :with_state
  has_scope :page, default: 1
  load_and_authorize_resource except: [:index]
  belongs_to :project
  before_filter :detect_old_browsers, only: [:new, :create]

  def update
    resource.update_attributes(params[:backer])
    resource.update_user_billing_info
    render json: {message: 'updated'}
  end

  def index
    render collection
  end

  def show
    @title = t('projects.backers.show.title')
  end

  def new
    unless parent.online?
      flash[:failure] = t('projects.back.cannot_back')
      return redirect_to :root
    end

    @create_url = ::Configuration[:secure_review_host] ?
      project_backers_url(@project, {host: ::Configuration[:secure_review_host], protocol: 'https'}) :
      project_backers_path(@project)

    @title = t('projects.backers.new.title', name: @project.name)
    @backer = @project.backers.new(user: current_user)
    empty_reward = Reward.new(minimum_value: 0, description: t('projects.backers.new.no_reward'))
    @rewards = [empty_reward] + @project.rewards.remaining.order(:minimum_value)

    # Select
    if params[:reward_id] && (@selected_reward = @project.rewards.find params[:reward_id]) && !@selected_reward.sold_out?
      @backer.reward = @selected_reward
      @backer.value = "%0.0f" % @selected_reward.minimum_value
    end
  end

  def create
    @title = t('projects.backers.create.title')
    @backer.user = current_user
    @backer.reward_id = nil if params[:backer][:reward_id].to_i == 0
    create! do |success,failure|
      failure.html do
        flash[:failure] = t('projects.backers.review.error')
        return redirect_to new_project_backer_path(@project)
      end
      success.html do
        resource.update_current_billing_info
        flash[:notice] = nil
        session[:thank_you_backer_id] = @backer.id
        return redirect_to edit_project_backer_path(project_id: @project.id, id: @backer.id)
      end
    end
    @thank_you_id = @project.id
  end

  def credits_checkout
    if current_user.credits < @backer.value
      flash[:failure] = t('projects.backers.checkout.no_credits')
      return redirect_to new_project_backer_path(@backer.project)
    end

    unless @backer.confirmed?
      @backer.update_attributes({ payment_method: 'Credits' })
      @backer.confirm!
    end
    flash[:success] = t('projects.backers.checkout.success')
    redirect_to project_backer_path(project_id: parent.id, id: resource.id)
  end

  protected
  def collection
    @backers ||= apply_scopes(end_of_association_chain).available_to_display.order("confirmed_at DESC").per(10)
  end
end
