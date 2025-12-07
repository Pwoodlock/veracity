# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # Default permissions - can be overridden in specific policies
  def index?
    user.present? && user.can_access_avo?
  end

  def show?
    user.present? && user.can_access_avo?
  end

  def create?
    user&.admin? || user&.operator?
  end

  def new?
    create?
  end

  def update?
    user&.admin? || user&.operator?
  end

  def edit?
    update?
  end

  def destroy?
    user&.admin?
  end

  # Avo-specific action permissions
  def act_on?
    update?
  end

  def reorder?
    update?
  end

  def search?
    index?
  end

  # Helper methods for role checking
  def admin?
    user&.admin?
  end

  def operator?
    user&.operator?
  end

  def viewer?
    user&.viewer?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      # By default, return all records if user can access Avo
      if user&.can_access_avo?
        scope.all
      else
        scope.none
      end
    end

    private

    attr_reader :user, :scope
  end
end
