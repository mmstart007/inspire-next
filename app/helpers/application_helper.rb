module ApplicationHelper

  BOOTSTRAP_FLASH_MSG ||= HashWithIndifferentAccess.new({
    success: 'alert-success',
    error:   'alert-error',
    alert:   'alert-danger',
    notice:  'alert-info'
  })

  def will_paginate(collection_or_options = nil, options={})
    if collection_or_options.is_a? Hash
      options,collection_or_options = collection_or_options,nil
    end
    unless options[:renderer]
      options = options.merge renderer: BootstrapPagination::Rails,  bootstrap: 3
    end
    super *[collection_or_options, options].compact
  end

  def print_or_dashes(text)
    text.blank? ? '---' : text
  end

  def action_types
    at = Action.child_classes.map { |klass| klass.to_s.to_sym }
    at = ::ACTION_TYPES if at.blank?
    at
  end

  def bootstrap_class_for(flash_type)
    BOOTSTRAP_FLASH_MSG.fetch(flash_type, flash_type.to_s)
  end

  def flash_messages(opts = {})
    flash.each do |msg_type, message|
      concat(
        content_tag(:div, message, class: "alert #{bootstrap_class_for(msg_type)} fade in") do
          concat content_tag(:button, 'x', class: "close", data: { dismiss: 'alert' })
          concat message
        end
      )
    end
    nil
  end

  def fu_number_helper(numx)
    # formats numbers for easier layout and for "precision versus accuracy"
    case numx
    when 0..999
      dec = numx
      incr = ""
    when 1000..999999
      dec = numx/1000.0
      incr = "K"
    when 1000000..999999999
      dec =  numx/1000000.0
      incr = "M"
    when 1000000000..999999999999
      dec =  numx/1000000000.0
      incr = "B"
    when 1000000000000..999999999999999
      dec = numx/1000000000000.0
      incr = "T"
    else
      dec = numx
      incr = ""
    end

    formatted_dec = (incr.eql?("") ? ("%.2f" % dec) : ("%.1f" % dec)) rescue dec

    return "#{formatted_dec.to_i}#{incr}"
  end

  def fu_time_helper(time)
    if time > (Time.now - 24.hours)
      "#{time.strftime("%H:%M")}"
    elsif (Time.now - 60.days) < time
      "#{time.strftime("%b %d")}"
    else
      "#{time.strftime("%b %y")}"
    end
  end

end
