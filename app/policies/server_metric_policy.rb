# frozen_string_literal: true

class ServerMetricPolicy < ApplicationPolicy
  # All authenticated users can view metrics
  def index?
    user.present? && user.can_access_avo?
  end

  def show?
    user.present? && user.can_access_avo?
  end

  # Metrics are collected automatically, not created manually
  def create?
    false
  end

  def update?
    false
  end

  # Only admins can delete metrics (for cleanup)
  def destroy?
    user&.admin?
  end

  # No actions allowed on metrics
  def act_on?
    false
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
