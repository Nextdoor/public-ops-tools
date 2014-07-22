require 'logger'

def get_logger
  $stdout.sync = true
  log = Logger.new($stdout)
  log.level = Logger::INFO
  return log
end
