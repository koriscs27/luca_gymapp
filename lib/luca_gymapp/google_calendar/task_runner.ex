defmodule LucaGymapp.GoogleCalendar.TaskRunner do
  def async(fun) when is_function(fun, 0) do
    Task.Supervisor.start_child(LucaGymapp.GoogleCalendarTaskSupervisor, fun)
  end
end
