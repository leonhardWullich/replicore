# Backend Integration: GraphQL

> **Setup guide for any GraphQL backend (Hasura, Apollo, Supabase GraphQL, etc.)**

---

## 🎯 When to Use GraphQL

**Best for**:
- Any GraphQL server (Hasura, Apollo, etc.)
- Type-safe queries
- Precise data fetching
- Federation-ready

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Setup** | ⭐⭐⭐⭐ | Depends on server |
| **Flexibility** | ⭐⭐⭐⭐⭐ | Works with any server |
| **Type Safety** | ⭐⭐⭐⭐⭐ | Code generation |
| **Batch Ops** | ⭐⭐⭐ | Parallel mutations |
| **Learning Curve** | ⭐⭐⭐ | GraphQL concepts |

---

## 📦 Installation

```bash
flutter pub add graphql
```

---

## 🚀 Setup

### Initialize GraphQL Client

```dart
import 'package:graphql/client.dart';

final httpLink = HttpLink('https://your-graphql-endpoint');

final authLink = AuthLink(
  getToken: () async => 'Bearer $token',
);

final link = authLink.concat(httpLink);

final client = GraphQLClient(
  link: link,
  cache: GraphQLCache(),
);
```

### Setup with Replicore

```dart
Future<SyncEngine> initializeReplicore() async {
  final db = await openAppDatabase();
  final localStore = SqfliteStore(db);
  
  final remoteAdapter = GraphQLAdapter(
    client: client,
  );
  
  final engine = SyncEngine(
    localStore: localStore,
    remoteAdapter: remoteAdapter,
  );
  
  await engine.init();
  return engine;
}
```

---

## 📋 GraphQL Setup (Hasura Example)

### Create Table Schema

```graphql
type Todo {
  id: UUID!
  uuid: String!
  title: String!
  description: String
  completed: Boolean!
  user_id: UUID!
  updated_at: DateTime!
  deleted_at: DateTime
  created_at: DateTime!
}

input TodoInsertInput {
  uuid: String!
  title: String!
  completed: Boolean!
  updated_at: DateTime!
  deleted_at: DateTime
  user_id: UUID!
}

input TodoUpdateInput {
  uuid: String!
  title: String
  completed: Boolean
  updated_at: DateTime
  deleted_at: DateTime
}

type Query {
  todos(where: TodoWhereInput): [Todo!]!
  todo(id: UUID!): Todo
}

type Mutation {
  createTodo(input: TodoInsertInput!): Todo!
  updateTodo(input: TodoUpdateInput!): Todo!
  deleteTodo(id: UUID!): Boolean!
}

type Subscription {
  todoUpdated: Todo!
}
```

---

## ✍️ Reading & Writing

### Query

```graphql
query GetTodos($userId: UUID!) {
  todos(where: { user_id: { eq: $userId } }) {
    id
    uuid
    title
    completed
    updated_at
    deleted_at
  }
}
```

### Implementation

```dart
final query = gql('''
  query GetTodos(\$userId: ID!) {
    todos(userId: \$userId) {
      id uuid title completed updated_at deleted_at
    }
  }
''');

final result = await client.query(
  QueryOptions(
    document: query,
    variables: {'userId': userId},
  ),
);

if (result.hasException) {
  print('Error: ${result.exception}');
} else {
  final todos = result.data?['todos'] as List;
}
```

### Mutation (Single)

```graphql
mutation CreateTodo($input: TodoInsertInput!) {
  createTodo(input: $input) {
    id uuid title updated_at
  }
}
```

### Batch Mutations

```dart
// GraphQL doesn't support native batch mutations
// Replicore uses parallel execution

final mutations = records.map((record) {
  return client.mutate(
    MutationOptions(
      document: gql('''
        mutation UpsertTodo(\$input: TodoInput!) {
          upsertTodo(input: \$input) {
            id uuid title
          }
        }
      '''),
      variables: {'input': record},
    ),
  );
}).toList();

final results = await Future.wait(mutations);
```

---

## 🔄 Real-Time Subscriptions

### Subscribe to Changes

```graphql
subscription OnTodoUpdated($userId: UUID!) {
  todoUpdated(userId: $userId) {
    id
    uuid
    title
    updated_at
    deleted_at
  }
}
```

### Implementation

```dart
final subscription = gql('''
  subscription OnTodoUpdated(\$userId: ID!) {
    todoUpdated(userId: \$userId) {
      id uuid title updated_at deleted_at
    }
  }
''');

client.subscribe(
  SubscriptionOptions(
    document: subscription,
    variables: {'userId': userId},
  ),
).listen((result) {
  if (result.hasException) {
    print('Subscription error: ${result.exception}');
  } else {
    // Trigger sync
    engine.sync();
  }
});
```

---

## 🔐 Authentication

### Include Token

```dart
final authLink = AuthLink(
  getToken: () async {
    final token = await _getAuthToken();
    return 'Bearer $token';
  },
);

final link = authLink.concat(httpLink);
```

### Handle Expired Token

```dart
final authLink = AuthLink(
  getToken: () async => 'Bearer $token',
  onAuthError: (AuthException error) async {
    // Refresh token
    final newToken = await _refreshToken();
    return 'Bearer $newToken';
  },
);
```

---

## ⚡ Performance Tips

### Use Fragments

```graphql
fragment TodoFields on Todo {
  id
  uuid
  title
  completed
  updated_at
  deleted_at
}

query GetTodos {
  todos {
    ...TodoFields
  }
}
```

### Pagination

```graphql
query GetTodos($limit: Int!, $offset: Int!) {
  todos(limit: $limit, offset: $offset) {
    id uuid title updated_at
  }
}
```

```dart
final result = await client.query(
  QueryOptions(
    document: query,
    variables: {
      'limit': 20,
      'offset': 0, // Second page: offset: 20
    },
  ),
);
```

---

## 🐛 Common Issues

### Issue: Introspection Denied

```
Error: introspection disabled
```

**Solution**: Enable introspection on server or use schema file

```dart
// Use pre-generated schema instead
import 'schema.gql.dart';
```

### Issue: Large Response

**Solution**: Limit fields in query

```graphql
# ❌ WRONG - Gets all fields
query GetTodos {
  todos { ... }
}

# ✅ RIGHT - Only needed fields
query GetTodos {
  todos {
    id
    title
    completed
  }
}
```

---

## 🧪 Testing

### Mock GraphQL

```dart
import 'package:graphql/client.dart';

final mockHttpLink = MockLink(
  operation: (request) async => Response(
    data: {'todos': []},
  ),
);

final testClient = GraphQLClient(
  link: mockHttpLink,
  cache: GraphQLCache(),
);
```

---

## 🚀 Production Checklist

- [ ] Schema documented
- [ ] Introspection secured
- [ ] Authentication implemented
- [ ] Subscriptions tested
- [ ] Error handling added
- [ ] Rate limiting configured
- [ ] Query complexity limited

---

**GraphQL is flexible and works with any backend!** 📡
