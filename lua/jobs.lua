-- Interface with Neovim job control and provide a simple job sequencing structure

local jobs = {}
local loop = vim.loop

local job_mt = {}
job_mt = {
  and_then = function(self, next_job)
    -- Run the next job if the previous job succeeded
    next_job.first  = self.first or self
    -- TODO: Need to make this a function that runs next only on success, else chains to the next
    -- next, etc.
    local next_success = setmetatable({}, job_mt)
    self.on_success = next_job
    return next_job
  end,

  __mul = function(prev, next_job)
    return prev:and_then(next_job)
  end,

  or_else = function(self, next_job)
    -- Run the next job if the previous job failed
    next_job.first = self.first or self
    self.on_failure = next_job
    return next_job
  end,

  __add = function(prev, next_job)
    return prev:or_else(next_job)
  end,

  start = function(self)
    local job = self.first or self
    job:__run()
  end,

  __run = function(self)
    if self.before then
      self.before()
    end

    local stdout = nil
    local stderr = nil
    if self.callbacks.stdout then
      stdout = loop.new_pipe(false)
    end

    if self.callbacks.stderr then
      stderr = loop.new_pipe(false)
    end

    local handle = nil
    handle = loop.spawn(self.task.cmd, {
      args = self.task.args,
      stdio = { stdout, stderr },
      hide = true
    },
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
      self:__exit(exit_code, signal)
    end)

    if stdout then
      loop.read_start(stdout, self.callbacks.stdout)
    end

    if stderr then
      loop.read_start(stderr, self.callbacks.stderr)
    end
  end,

  __exit = function(self, exit_code, signal)
    local success = self.callbacks.exit(exit_code, signal)
    if self.after then
      self.after(success)
    end

    if success and self.on_success then
      self.on_success:run()
    elseif not success and self.on_failure then
      self.job.on_failure:run()
    else
      self:__done()
    end
  end,

  __done = function(self)
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
