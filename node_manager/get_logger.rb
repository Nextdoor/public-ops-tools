require 'logger'

def get_logger
  log = Logger.new(STDOUT)
  log.level = Logger::INFO
  log.level = Logger::DEBUG
  return log
end
