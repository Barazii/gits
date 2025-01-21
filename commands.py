from scheduler import schedule_push, schedule_commit
from storage import add_task, load_tasks, remove_task

def schedule_push_cmd(timestamp):
    task = {'type': 'push', 'timestamp': timestamp}
    task_id = add_task(task)
    dt = schedule_push(timestamp)
    print(f'Push (ID {task_id}) scheduled for {dt}')

def schedule_commit_cmd(message, timestamp):
    task = {'type': 'commit', 'message': message, 'timestamp': timestamp}
    task_id = add_task(task)
    dt = schedule_commit(message, timestamp)
    print(f'Commit (ID {task_id}) scheduled for {dt}')

def list_tasks_cmd():
    tasks = load_tasks()
    for task in tasks:
        print(f"ID: {task['id']}, Type: {task['type']}, Timestamp: {task['timestamp']}")

def cancel_task_cmd(task_id):
    remove_task(task_id)
    print(f'Task {task_id} cancelled')