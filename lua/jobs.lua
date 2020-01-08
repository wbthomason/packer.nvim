-- Interface with Neovim job control and provide a simple job sequencing monad

local jobs = {}

local context_store = {}

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
    self.run(self.job)
  end,

  run = function(job)
    vim.fn.jobstart(job.task,
      { on_stdout = 'plague#handle_callback',
        on_stderr = 'plague#handle_callback',
        on_exit   = 'plague#handle_callback',
        ctx_id    = job.ctx.id,
        ctx_job   = job.id })
  end,

  stdout = function(self, job_id, data, event)
    self.job.callbacks.stdout(job_id, data, event)
  end,

  stderr = function(self, job_id, data, event)
    self.job.callbacks.stderr(job_id, data, event)
  end,

  exit = function(self, job_id, exit_code, event)
    local success = self.job.callbacks.exit(job_id, exit_code, event)
    if success and self.job.on_success then
      self.job = self.job.on_success
      self.run(self.job)
    elseif not success and self.job.on_failure then
      self.job = self.job.on_failure
      self.run(self.job)
    else
      self:done()
    end
  end,

  done = function(self)
    self.ctx:job_done(self)
  end
}

local Context = {
  next_id = 1
}

function Context:get_job(id)
  return self.jobs[id]
end

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

function Context:deactivate()
  context_store[self.id] = nil
end

jobs.new = function(max_jobs, after_done)
  local ctx             = setmetatable({}, { __index = Context })
  ctx.queue             = {}
  ctx.max_jobs          = max_jobs
  ctx.jobs              = {}
  ctx.after_done        = after_done
  ctx.id                = 'ctx_' .. ctx.next_id
  ctx.next_id           = ctx.next_id + 1
  context_store[ctx.id] = ctx
  return ctx
end

jobs.get_context = function(id)
  return context_store[id]
end

return jobs
