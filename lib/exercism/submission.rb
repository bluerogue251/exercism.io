class Submission < ActiveRecord::Base
  serialize :solution, JSON
  belongs_to :user
  belongs_to :user_exercise
  has_many :comments, ->{ order(created_at: :asc) }, dependent: :destroy

  # I don't really want the notifications method,
  # just the dependent destroy
  has_many :notifications, ->{ where(item_type: 'Submission') }, dependent: :destroy, foreign_key: 'item_id', class_name: 'Notification'

  has_many :submission_viewers, dependent: :destroy
  has_many :viewers, through: :submission_viewers

  has_many :muted_submissions, dependent: :destroy
  has_many :muted_by, through: :muted_submissions, source: :user

  has_many :likes, dependent: :destroy
  has_many :liked_by, through: :likes, source: :user

  validates_presence_of :user

  before_create do
    self.state          ||= "pending"
    self.nit_count      ||= 0
    self.version        ||= 0
    self.is_liked       ||= false
    self.key            ||= Exercism.uuid
    true
  end

  scope :chronologically, ->{ order(created_at: :asc) }
  scope :reversed,        ->{ order(created_at: :desc) }

  scope :older_than, ->(timestamp)            { where('created_at < ?', timestamp) }
  scope :since,      ->(timestamp)            { where('created_at > ?', timestamp) }
  scope :between,    ->(start_time, end_time) { where(created_at: start_time..end_time) }

  scope :recent, ->{ since(7.days.ago) }
  scope :aging,  ->{ pending.where('nit_count > 0').older_than(3.weeks.ago) }

  scope :done,        ->{ where(state: 'done') }
  scope :pending,     ->{ where(state: %w(needs_input pending)) }
  scope :hibernating, ->{ where(state: 'hibernating') }
  scope :needs_input, ->{ where(state: 'needs_input') }

  scope :not_commented_on_by, ->(user) {
    where("id NOT IN (#{Comment.where(user: user).select(:submission_id).to_sql})")
  }

  scope :not_liked_by, ->(user) {
    where("id NOT IN (#{Like.where(user: user).select(:submission_id).to_sql})")
  }

  scope :unmuted_for, ->(user) {
    where("id NOT IN (#{MutedSubmission.where(user: user).select(:submission_id).to_sql})")
  }

  scope :not_submitted_by, ->(user) {
    where.not(user: user)
  }

  scope :for_language, ->(language) {
    where(language: language)
  }

  scope :completed_for,        ->(problem)    { done.for(problem) }
  scope :random_completed_for, ->(problem)    { done.for(problem).order('RANDOM()').first }
  scope :related,              ->(submission) { chronologically.for(submission).where(user_id: submission.user_id) }
  scope :for,                  ->(problem)    { where(language: problem.track_id, slug: problem.slug) }

  def self.on(problem)
    submission = new
    submission.on problem
    submission.save
    submission
  end

  def discussion_involves_user?
    nit_count < comments.count
  end

  def name
    @name ||= slug.split('-').map(&:capitalize).join(' ')
  end

  def older_than?(time)
    created_at.utc < (Time.now.utc - time)
  end

  def track_id
    language
  end

  def problem
    @problem ||= Problem.new(track_id, slug)
  end

  def on(problem)
    self.language = problem.track_id
    self.slug     = problem.slug
  end

  def supersede!
    self.state   = 'superseded'
    self.done_at = nil
    save
  end

  def like!(user)
    self.is_liked = true
    self.liked_by << user unless liked_by.include?(user)
    mute(user)
    save
  end

  def unlike!(user)
    likes.where(user_id: user.id).destroy_all
    self.is_liked = liked_by.length > 0
    unmute(user)
    save
  end

  def liked?
    is_liked
  end

  def done?
    state == 'done'
  end

  def pending?
    state == 'pending'
  end

  def hibernating?
    state == 'hibernating'
  end

  def superseded?
    state == 'superseded'
  end

  def muted_by?(user)
    muted_submissions.where(user_id: user.id).exists?
  end

  def mute(user)
    muted_by << user
  end

  def mute!(user)
    mute(user)
    save
  end

  def unmute(user)
    muted_submissions.where(user_id: user.id).destroy_all
  end

  def unmute!(user)
    unmute(user)
    save
  end

  def unmute_all!
    muted_by.clear
    save
  end

  def viewed!(user)
    begin
      self.viewers << user unless viewers.include?(user)
    rescue => e
      # Temporarily output this to the logs
      puts "#{e.class}: #{e.message}"
    end
  end

  def view_count
    viewers.count
  end

  def exercise_completed?
    user_exercise.completed?
  end

  def exercise_hibernating?
    user_exercise.hibernating?
  end

  def prior
    @prior ||= related.where(version: version-1).first
  end

  def related
    @related ||= Submission.related(self)
  end

  private

  # Experiment: Cache the iteration number so that we can display it
  # on the dashboard without pulling down all the related versions
  # of the submission.
  # Preliminary testing in development suggests an 80% improvement.
  before_create do |document|
    self.version = Submission.related(self).count + 1
  end
end
