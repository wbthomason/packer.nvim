-- Interface with Neovim job control and provide a simple job sequencing structure

local jobs = {}
local loop = vim.loop

local job_mt = {}
job_mt = {
  -- TODO: It would probably be nice to allow raw tables to be passed here and construct a job in
  -- the right context if needed
  and_then = function(self, next_job)
    -- Run the next job if the previous job succeeded
    next_job.first  = self.first or self
    self.next = function(success, data)
      if success then
        next_job:__run(data)
      elseif next_job.next then
        next_job.next(success, data)
      elseif next_job.finally then
        -- This means the next job is the last link in the chain,is not supposed to run on success,
        -- and has a "chain-ender" function to run
        next_job.finally(success)
      end
    end

    return next_job
  end,

  __mul = function(prev, next_job)
    return prev:and_then(next_job)
  end,

  or_else = function(self, next_job)
    -- Run the next job if the previous job failed
    next_job.first = self.first or self
    self.next = function(success, data)
      if not success then
        next_job:__run(data)
      elseif next_job.next then
        next_job.next(success, data)
      elseif next_job.finally then
        -- This means the next job is the last link in the chain,is not supposed to run on success,
        -- and has a "chain-ender" function to run
        next_job.finally(success)
      end
    end
  end,

  __add = function(prev, next_job)
    return prev:or_else(next_job)
  end,

  start = function(self)
    local job = self.first or self
    job:__run()
  end,

  __run = function(self, data)
    if self.before then
      self.before(data)
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
    local success = self.callbacks.exit and self.callbacks.exit(exit_code, signal) or (exit_code == 0)
    local data = nil
    if self.after then
      data = self.after(success)
    end

    if self.next then
      self.next(success, data)
    else
      if self.finally then
        self.finally(success, data)
      end

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
  if not job.callbacks then
    job.callbacks = {}
  end

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
  self.jobs[job.id] = nil
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
  ctx.max_jobs          = max_jobs or math.huge
  ctx.jobs              = {}
  ctx.after_done        = after_done
  return ctx
end

return jobs
