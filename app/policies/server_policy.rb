# frozen_string_literal: true

class ServerPolicy < ApplicationPolicy
  # All authenticated users can view servers
  def index?
    user.present? && user.can_access_avo?
  end

  def show?
    user.present? && user.can_access_avo?
  end

  # Admin and operators can create/update servers
  def create?
    user&.admin? || user&.operator?
  end

  def update?
    user&.admin? || user&.operator?
  end

  # Only admins can delete servers
  def destroy?
    user&.admin?
  end

  # Avo actions - operators and admins can perform server actions
  def act_on?
    user&.admin? || user&.operator?
  end

  def ping?
    act_on?
  end

  def run_command?
    act_on?
  end

  def collect_metrics?
    act_on?
  end

  def refresh_grains?
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
