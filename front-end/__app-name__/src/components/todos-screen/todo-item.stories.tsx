import type { Meta, StoryObj } from '@storybook/react'
import TodoItem from './todo-item'

const meta: Meta<typeof TodoItem> = {
    title: 'Todos/TodoItem',
    component: TodoItem,
}

export default meta

type Story = StoryObj<typeof TodoItem>

export const Incomplete: Story = {
    args: {
        todo: {
            id: 1,
            title: 'Buy milk',
            description: 'From the corner store',
            is_completed: false,
            user_id: 1,
            created_at: '2026-01-01T00:00:00Z',
            updated_at: '2026-01-01T00:00:00Z',
        },
        onToggle: () => {},
        onEdit: () => {},
    },
}

export const Completed: Story = {
    args: {
        ...Incomplete.args,
        todo: { ...Incomplete.args!.todo!, is_completed: true },
    },
}
