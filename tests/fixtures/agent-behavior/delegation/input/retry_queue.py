"""Return retry delays for failed jobs."""


class RetryQueue:
    def __init__(self, base_delay=2, max_delay=30):
        self.base_delay = base_delay
        self.max_delay = max_delay
        self.attempt = 0

    def failure(self, job_id):
        self.attempt += 1
        return min(self.base_delay * self.attempt, self.max_delay)

    def success(self, job_id):
        self.attempt = 0
