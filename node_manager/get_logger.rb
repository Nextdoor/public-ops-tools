require 'logger'

def get_logger
  log = Logger.new(STDOUT)
  log.level = Logger::INFO
  return log
end
