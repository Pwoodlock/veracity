# frozen_string_literal: true

class CommandPolicy < ApplicationPolicy
  # All authenticated users can view commands
  def index?
    user.present? && user.can_access_avo?
  end

  def show?
    user.present? && user.can_access_avo?
  end

  # Admin and operators can create commands
  def create?
    user&.admin? || user&.operator?
  end

  # Commands cannot be edited once created (immutable audit trail)
  def update?
    false
  end

  # Only admins can delete commands (for cleanup/compliance)
  def destroy?
    user&.admin?
  end

  # Operators and admins can perform command actions
  def act_on?
    user&.admin? || user&.operator?
  end

  def cancel?
    act_on?
  end

  def retry?
    act_on?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.can_access_avo?
        scope.all
      else
        scope.none
      end
    end
  end
end
