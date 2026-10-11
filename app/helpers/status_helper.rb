module StatusHelper
  # "5.4s", or "-" while the run has not finished.
  def run_duration(run)
    return "-" unless run.started_at && run.finished_at

    "#{number_with_precision(run.finished_at - run.started_at, precision: 1)}s"
  end

  def run_time(time)
    time ? time.strftime("%b %-d, %H:%M:%S") : "-"
  end
end
