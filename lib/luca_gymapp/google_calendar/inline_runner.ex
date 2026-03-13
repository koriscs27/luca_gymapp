defmodule LucaGymapp.GoogleCalendar.InlineRunner do
  def async(fun) when is_function(fun, 0) do
    fun.()
    {:ok, self()}
  end
end
