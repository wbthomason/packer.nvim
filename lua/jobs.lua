-- Interface with Neovim job control and provide a simple job sequencing monad

local jobs = {}
local loop = vim.loop

local job_mt = {
  __mul = function(prev, next_job)
    -- Roughly the "And" operator; runs the next job if the previous job succeeded
    next_job.first  = prev.first or prev
    prev.on_success = next_job
    return next_job
  end,

  __add = function(prev, next_job)
    -- Roughly the "Or" operator; runs the next job if the previous job failed
    next_job.first = prev.first or prev
    prev.on_failure = next_job
    return next_job
  end,

  start = function(self)
    self.job = self.first or self
    self:run(self.job)
  end,

  run = function(self, job)

    local stdout = nil
    local stderr = nil
    if job.callbacks.stdout then
      stdout = loop.new_pipe(false)
    end

    if job.callbacks.stderr then
      stderr = loop.new_pipe(false)
    end

    local handle = nil
    handle = loop.spawn(job.task.cmd, {
      args = job.task.args,
      stdio = { stdout, stderr },
      hide = true
    },
    vim.schedule_wrap(
      function(exit_code, signal)
        if stdout then
          stdout:read_stop()
          stdout:close()
        end

        if stderr then
          stderr:read_stop()
          stderr:close()
        end

        handle:close()
        self:exit(exit_code, signal)
      end))

    if stdout then
      loop.read_start(stdout, job.callbacks.stdout)
    end

    if stderr then
      loop.read_start(stderr, job.callbacks.stderr)
    end
  end,

  exit = function(self, exit_code, signal)
    local success = self.job.callbacks.exit(exit_code, signal)
    if success and self.job.on_success then
      self.job = self.job.on_success
      self:run(self.job)
    elseif not success and self.job.on_failure then
      self.job = self.job.on_failure
      self:run(self.job)
    else
      self:done()
    end
  end,

  done = function(self)
    self.ctx:job_done(self)
  end
}

local Context = {}

function Context:new_job(job_data)
  job_data  = job_data or {}
  local job = setmetatable(job_data, job_mt)
  job.ctx   = self
  return job
end

function Context:start(job)
  if #self.jobs > self.max_jobs then
    table.insert(self.queue, job)
  else
    job.id = 'job_' .. #self.jobs
    self.jobs[job.id] = job
    job:start()
  end
end

function Context:job_done(job)
  self.jobs[job.idx] = nil
  if #self.jobs == 0 then
    self:all_done()
  else
    local next_job = table.remove(self.queue, 1)
    next_job.id = job.id
    self.jobs[job.id] = next_job
    next_job:start()
  end
end

function Context:all_done()
  if self.after_done then
    self.after_done()
  end
end

jobs.new = function(max_jobs, after_done)
  local ctx             = setmetatable({}, { __index = Context })
  ctx.queue             = {}
  ctx.max_jobs          = max_jobs
  ctx.jobs              = {}
  ctx.after_done        = after_done
  return ctx
end

return jobs
