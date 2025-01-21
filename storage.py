import json

TASK_FILE = 'tasks.json'

def load_tasks():
    try:
        with open(TASK_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return []

def save_tasks(tasks):
    with open(TASK_FILE, 'w') as f:
        json.dump(tasks, f)

def add_task(task):
    tasks = load_tasks()
    task['id'] = len(tasks) + 1
    tasks.append(task)
    save_tasks(tasks)
    return task['id']

def remove_task(task_id):
    tasks = load_tasks()
    tasks = [task for task in tasks if task['id'] != task_id]
    save_tasks(tasks)