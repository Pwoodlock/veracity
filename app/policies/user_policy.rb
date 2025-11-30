# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  # Only admins can view the user list
  def index?
    user&.admin?
  end

  # Admins can view any user, users can view themselves
  def show?
    user&.admin? || record == user
  end

  # Only admins can create users
  def create?
    user&.admin?
  end

  # Only admins can update users
  def update?
    user&.admin?
  end

  # Only admins can delete users (except themselves)
  def destroy?
    user&.admin? && record != user
  end

  # Only admins can perform user actions
  def act_on?
    user&.admin?
  end

  def lock?
    user&.admin? && record != user
  end

  def unlock?
    user&.admin? && record != user
  end

  def change_role?
    user&.admin? && record != user
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin?
        scope.all
      else
        # Non-admins can only see themselves
        scope.where(id: user.id)
      end
    end
  end
end
