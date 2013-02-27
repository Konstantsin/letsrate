require 'active_support/concern'
module Letsrate
  extend ActiveSupport::Concern

  def rate(stars, user_id, dimension=nil)
    ActiveRecord::Base.transaction do
      if has_rated? user_id, dimension
        rating = existing_ratings(user_id, dimension).first
        old_stars = rating.stars
        rating.stars = stars
        rating.save

        a = average(dimension)
        if a.qty == 1
          a.avg = rating.stars
        else
          # "remove" old rating
          a.avg = (a.avg * a.qty - old_stars) / (a.qty - 1)
          a.qty = a.qty - 1
          # "add" new rating
          a.avg = (a.avg * a.qty + stars) / (a.qty + 1)
          a.qty = a.qty + 1
        end
        a.save
      else
        update_rate_average(stars, dimension)
        rates(dimension).create do |r|
          r.stars = stars
          r.rater_id = user_id
        end
      end
    end
  end

  def existing_ratings(user_id, dimension=nil)
    Rate.where(rateable_id: self.id, rateable_type: self.class.name, rater_id: user_id, dimension: dimension)
  end

  def has_rated?(user_id, dimension=nil)
    existing_ratings(user_id, dimension).any?
  end

  def cancel_rating(user_id, dimension=nil)
    ActiveRecord::Base.transaction do
      rating = existing_ratings(user_id, dimension).first
      a = average(dimension)
      if a.qty <= 1
        a.destroy
      else
        a.avg = (a.avg * a.qty - rating.stars) / (a.qty - 1)
        a.qty = a.qty - 1
        a.save
      end
      rating.destroy
    end
  end

  def update_rate_average(stars, dimension=nil)
    if average(dimension).nil?
      RatingCache.create do |avg|
        avg.cacheable_id = self.id
        avg.cacheable_type = self.class.name
        avg.avg = stars
        avg.qty = 1
        avg.dimension = dimension
      end
    else
      a = average(dimension)
      a.avg = (a.avg*a.qty + stars) / (a.qty+1)
      a.qty = a.qty + 1
      a.save
    end
  end

  def average(dimension=nil)
    if dimension.nil?
      self.send "rate_average_without_dimension"
    else
      self.send "#{dimension}_average"
    end
  end

  def can_rate?(user_id, dimension=nil)
    ! has_rated?(user_id, dimension)
  end

  def rates(dimension=nil)
    if dimension.nil?
      self.send "rates_without_dimension"
    else
      self.send "#{dimension}_rates"
    end
  end

  def raters(dimension=nil)
    if dimension.nil?
      self.send "raters_without_dimension"
    else
      self.send "#{dimension}_raters"
    end
  end

  module ClassMethods

    def letsrate_rater
      has_many :ratings_given, :class_name => "Rate", :foreign_key => :rater_id
    end

    def letsrate_rateable(*dimensions)
      has_many :rates_without_dimension, :as => :rateable, :class_name => "Rate", :dependent => :destroy, :conditions => {:dimension => nil}
      has_many :raters_without_dimension, :through => :rates_without_dimension, :source => :rater

      has_one :rate_average_without_dimension, :as => :cacheable, :class_name => "RatingCache",
              :dependent => :destroy, :conditions => {:dimension => nil}


      dimensions.each do |dimension|
        has_many :"#{dimension}_rates", :dependent => :destroy,
                                       :conditions => {:dimension => dimension.to_s},
                                       :class_name => "Rate",
                                       :as => :rateable

        has_many :"#{dimension}_raters", :through => "#{dimension}_rates", :source => :rater

        has_one :"#{dimension}_average", :as => :cacheable, :class_name => "RatingCache",
                                        :dependent => :destroy, :conditions => {:dimension => dimension.to_s}
      end
    end
  end

end

class ActiveRecord::Base
  include Letsrate
end
