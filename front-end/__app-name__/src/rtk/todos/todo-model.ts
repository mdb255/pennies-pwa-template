export interface Todo {
    id: number
    title: string
    description: string | null
    is_completed: boolean
    user_id: number
    created_at: string
    updated_at: string
}

export interface TodoCreate {
    title: string
    description?: string | null
    is_completed?: boolean
}

export interface TodoUpdate {
    title?: string
    description?: string | null
    is_completed?: boolean
}

export interface TodosQueryParams {
    skip?: number
    limit?: number
    is_completed?: boolean
}
