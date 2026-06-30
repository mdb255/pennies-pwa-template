import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import TodoItem from './todo-item'
import type { Todo } from '../../rtk/todos/todo-model'

const todo: Todo = {
    id: 1,
    title: 'Buy milk',
    description: null,
    is_completed: false,
    user_id: 1,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
}

describe('TodoItem', () => {
    it('renders the todo title', () => {
        render(<TodoItem todo={todo} onToggle={vi.fn()} onEdit={vi.fn()} />)
        expect(screen.getByText('Buy milk')).toBeInTheDocument()
    })

    it('renders the description when present', () => {
        render(<TodoItem todo={{ ...todo, description: 'From the corner store' }} onToggle={vi.fn()} onEdit={vi.fn()} />)
        expect(screen.getByText('From the corner store')).toBeInTheDocument()
    })
})
