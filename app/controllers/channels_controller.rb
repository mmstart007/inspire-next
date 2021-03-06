class ChannelsController < ApplicationController
  include Mixins::SubscriberSearch
  include Mixins::ChannelSearch
  include Mixins::ChannelGroupSearch
  include Mixins::MessageSearch
  include Mixins::AdministrativeLogging
  before_action :load_channel
  skip_before_action :load_channel, only: %i(
      new create index add_subscriber remove_subscriber
    )
  before_action :load_user, only: %i(new create update index)
  before_action :load_subscriber, only: %i(add_subscriber remove_subscriber)

  decorates_assigned :messages

  def index
    session[:root_page] = channels_path
    handle_channel_query
    handle_channel_group_query
    respond_to do |format|
      format.html #index.html.erb
      format.json { render json: @channels }
    end
  end

  def show
    if @channel
      handle_subscribers_query
      @messages = @channel.messages
      @messages = @messages.search(params[:message_search]) if params[:message_search]

      @message_counts_by_type = { "All" => @messages.size }
      %w(ActionMessage PollMessage ResponseMessage SimpleMessage TagMessage).each do |message_type|
        count = @messages.where(type: message_type).size
        @message_counts_by_type[message_type] = count if count > 0
      end

      if params[:message_type].present? && params[:message_type] != "All"
        @messages = @messages.where(type: params[:message_type])
      end

      @messages = if @channel.sequenced?
        @messages.order(:seq_no)
      elsif @channel.individual_messages_have_schedule?
        @messages.order(:created_at)
      else
        @messages.order(created_at: :desc)
      end

      @messages = @messages
        .sort { |x, y| x.target_time <=> y.target_time }
        .paginate(page: params[:messages_page], per_page: 10)
    end

    respond_to do |format|
      format.html
      format.json { render json: @channel }
    end
  end

  def new
    @channel = @user.channels.new
    if params["channel_group_id"].present?
      ch_group = @user.channel_groups.find(params["channel_group_id"])
      @channel.channel_group = ch_group if ch_group
    end

    respond_to do |format|
      format.html
      format.json { render json: @channel }
    end
  end

  def all
    if @channel
      @messages = @channel.messages
      @messages = @messages.search(params[:message_search]) if params[:message_search]

      @message_counts_by_type = { "All" => @messages.size }
      %w(ActionMessage PollMessage ResponseMessage SimpleMessage TagMessage).each do |message_type|
        count = @messages.where(type: message_type).size
        @message_counts_by_type[message_type] = count if count > 0
      end

      if params[:message_type].present? && params[:message_type] != "All"
        @messages = @messages.where(type: params[:message_type])
      end

      @messages = if @channel.sequenced?
        @messages.order(:seq_no)
      elsif @channel.individual_messages_have_schedule?
        @messages.order(:created_at)
      else
        @messages.order(created_at: :desc)
      end

      @messages = @messages
        .sort { |x, y| x.seq_no <=> y.seq_no }
    end

    respond_to do |format|
      format.html
      format.json { render json: @channel }
    end
  end

  def edit; end

  def create
    @channel = ChannelFactory.new(params, nil, @user, @channel_group).channel
    respond_to do |format|
      if @channel.save
        log_user_activity("Created channel #{@channel.id}-#{@channel.name}", {channel_id: @channel.id})
        format.html { redirect_to [@channel], notice: 'Channel was successfully created.' }
        format.json { render json: @channel, status: :created, location: [@channel] }
      else
        format.html { render action: "new", alert: @channel.errors.full_messages.join(", and ")}
        format.json { render json: @channel.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    original_channel = Channel.find(params[:id])
    @channel = ChannelFactory.new(params, original_channel, @user, @channel_group).channel
    respond_to do |format|
      if @channel.save
        log_user_activity("Changed channel #{@channel.id}-#{@channel.name}", {channel_id: @channel.id})
        format.html { redirect_to @channel, notice: 'Channel was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @channel.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    log_user_activity("Destroyed channel #{@channel.id}-#{@channel.name}", {channel_id: @channel.id})
    @channel.destroy

    respond_to do |format|
      format.html { redirect_to user_url(@user) }
      format.json { head :no_content }
    end
  end

  def list_subscribers
    subscribed_subscribers = @channel.subscribers
    subs_subs_ids = subscribed_subscribers.map(&:id)
    @subscribed_subscribers = @channel.subscribers
      .page(params[:subscribed_subscribers_page])
      .per_page(10)

    @unsubscribed_subscribers = if subs_subs_ids.size == 0
      @user.subscribers
        .page(params[:unsubscribed_subscribers_page])
        .per_page(10)
    else
      @user.subscribers
        .where("id not in (?)", subs_subs_ids)
        .page(params[:unsubscribed_subscribers_page])
        .per_page(10)
    end

    respond_to do |format|
      format.html
      format.json { render json: @channel }
    end
  end

  def add_subscriber
    already_subscribed = @channel.subscribers.where(id: @subscriber.id).first
    notice = "Subscriber already added a member of the channel group. No changes made."

    unless already_subscribed
      if @channel.subscribers.push @subscriber
        log_user_activity("Added subscriber #{@subscriber.id}-#{@subscriber.name} to #{@channel.id}-#{@channel.name}", {'subscriber_id' => @subscriber.id, channel_id: @channel.id})
        notice = "Subscriber added to channel."
      else
        error = "Subscriber is already a member of a channel in the channel group. Cannot add."
      end
    end

    respond_to do |format|
      format.html { redirect_to :back, notice: notice }
      format.json { render json: @channel.subscribers, location: [@channel] }
    end
  end

  def remove_subscriber
    already_subscribed = @channel.subscribers.where(id: @subscriber.id).first
    notice = "Subscriber not currently subscribed to this channel. No changes done."

    if already_subscribed
      @channel.subscribers.destroy @subscriber
      log_user_activity("Removed subscriber #{@subscriber.id}-#{@subscriber.name} from #{@channel.id}-#{@channel.name}", {'subscriber_id' => @subscriber.id, channel_id: @channel.id})
      notice = "Subscriber removed from channel."
    end

    respond_to do |format|
      format.html { redirect_to :back, notice: notice }
      format.json { render json: @channel.subscribers, location: [@channel] }
    end
  end

  def messages_report
    respond_to do |format|
      format.csv {send_data @channel.messages_report}
    end
  end

  def rollback_notification
    error = "Subscriber not added, because the are already a subscribed to a channel in the group."
  end

  def delete_all_messages
    @channel.messages.delete_all
    log_user_activity("Deleted all messages in #{@channel.id}-#{@channel.name}", {channel_id: @channel.id})
    redirect_to :back, notice: "All messages were deleted."
  end

  def export
    helper = ExportChannel.new(@channel.id)
    log_user_activity("Exported messages in #{@channel.id}-#{@channel.name}", {channel_id: @channel.id})
    respond_to do |format|
      format.csv { send_data helper.to_csv, filename: "channel-#{@channel.id}-messages-#{Date.today}.csv" }
    end
  end

  private

    def channel_params
      params.require(:channel)
        .permit(
          :description, :name, :type, :keyword, :tparty_keyword, :schedule,
          :channel_group_id, :one_word, :suffix, :moderator_emails,
          :real_time_update, :relative_schedule, :send_only_once, :active,
          :allow_mo_subscription, :mo_subscription_deadline
        )
    end

    def load_user
      authenticate_user!
      @user = current_user
    end

    def load_channel
      authenticate_user!
      @user = current_user
      @channel = @user.channels.find(params[:id])
      redirect_to root_url, alert: "Access Denied" unless @channel
    rescue ActiveRecord::RecordNotFound
      redirect_to root_url, alert: "Access Denied"
    end

    def load_subscriber
      authenticate_user!
      @user = current_user
      @channel = @user.channels.find(params[:channel_id])
      redirect_to root_url, alert: "Access Denied" unless @channel
      @subscriber = @user.subscribers.find(params[:id])
      redirect_to root_url, alert: "Access Denied" unless @subscriber
    rescue ActiveRecord::RecordNotFound
      redirect_to root_url, alert: "Access Denied"
    end
end
