class DashboardController < ApplicationController
  def index
    render inertia: "Dashboard", props: DashboardStats.new.to_h
  end
end
