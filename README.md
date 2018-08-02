# ActiveRecord OR Precedence

As of Rails 5, ActiveRecord supports the `OR` operator. The docs 
[give a simple example](http://devdocs.io/rails~5.0/activerecord/querymethods#method-i-or) 
of how to use it:

```ruby
Post.where("id = 1").or(Post.where("author_id = 3"))
# SELECT `posts`.* FROM `posts`  WHERE (('id = 1' OR 'author_id = 3'))
```

The BigBinary Blog also has a 
[nice article](https://blog.bigbinary.com/2016/05/30/rails-5-adds-or-support-in-active-record.html) 
introducing the feature with some richer examples, including scopes, how to use it in a `HAVING`
clause, and some of the limitations.

One thing I couldn't find was information about how to control the precedence of `OR` expressions
when mixed with `AND`. In raw SQL, this is done simply with parentheses, but I wasn't sure how to
do this with ActiveRecord's `or` method, so I did some experimenting and wrote this up (...which 
will guarantee that I'll find some existing docs after publishing this). 

Let's start with this table of data. You can also reference this Ruby code 
[or_precedence.rb](https://github.com/chrismo/activerecord_or_precedence/blob/master/or_precedence.rb)
for the ActiveRecord models and specs used to demonstrate items in this article.

```
+--------------+-------+----------+--------+
|     name     | state | order_id | amount |
+--------------+-------+----------+--------+
| Texas Person | TX    | 9        | 30     |
| Texas Person | TX    | 10       | 46     |
| Maine Person | ME    | 11       | 30     |
| Maine Person | ME    | 12       | 120    |
+--------------+-------+----------+--------+
```

In this example, no parentheses are required, because `AND` has a 
[higher precedence](https://www.postgresql.org/docs/10/static/sql-syntax-lexical.html#SQL-PRECEDENCE) 
than `OR`, so the following two SQL examples are equivalent:

```sql
SELECT c.name, a.state, o.id as order_id, o.amount
FROM clients c
       INNER JOIN addresses a ON c.id = a.client_id
       INNER JOIN orders o ON c.id = o.client_id
WHERE (a.state = "TX" AND o.amount < 40) OR (a.state = "ME" AND o.amount > 100)
ORDER BY o.id
```

```sql
SELECT c.name, a.state, o.id as order_id, o.amount
FROM clients c
       INNER JOIN addresses a ON c.id = a.client_id
       INNER JOIN orders o ON c.id = o.client_id
WHERE a.state = "TX" AND o.amount < 40 OR a.state = "ME" AND o.amount > 100
ORDER BY o.id
```

The ActiveRecord 5.0 version of this query...
```ruby
base = Client.select("name, amount").joins(:address, :orders)
result = base.where(addresses: {state: "TX"})
           .where("orders.amount < ?", 40)
           .or(
             base.where(addresses: {state: "ME"})
               .where("orders.amount > ?", 100)
           )
           .order("orders.id")
```

...will emit this SQL, with some minor ugly use of parentheses, but essentially it is also relying
on the natural precedence of `AND` and `OR`. 
```sql
SELECT name, amount
FROM "clients"
       INNER JOIN "addresses" ON "addresses"."client_id" = "clients"."id"
       INNER JOIN "orders" ON "orders"."client_id" = "clients"."id"
WHERE ("addresses"."state" = "TX" AND (orders.amount < 40) 
   OR  "addresses"."state" = "ME" AND (orders.amount > 100))
ORDER BY orders.id  
```

But what happens if I need to ensure the precedence of an `OR` expression? In the following SQL statement,
the parentheses around `OR` change how the query is evaluated. This query will retrieve only Texas orders
with an amount less than 40 or greater than 100:
```sql
SELECT c.name, a.state, o.id as order_id, o.amount
FROM clients c
       INNER JOIN addresses a ON c.id = a.client_id
       INNER JOIN orders o ON c.id = o.client_id
WHERE a.state = "TX" AND (o.amount < 40 OR o.amount > 100)
ORDER BY o.id
```
```
+--------------+-------+----------+--------+
|     name     | state | order_id | amount |
+--------------+-------+----------+--------+
| Texas Person | TX    | 9        | 30     |
+--------------+-------+----------+--------+
```

Without the parentheses, the `AND` takes precedence and we get a different result set:
```sql
SELECT c.name, a.state, o.id as order_id, o.amount
FROM clients c
       INNER JOIN addresses a ON c.id = a.client_id
       INNER JOIN orders o ON c.id = o.client_id
WHERE a.state = "TX" AND o.amount < 40 OR o.amount > 100
ORDER BY o.id
```
```
+--------------+-------+----------+--------+
|     name     | state | order_id | amount |
+--------------+-------+----------+--------+
| Texas Person | TX    | 9        | 30     |
| Maine Person | ME    | 12       | 120    |
+--------------+-------+----------+--------+
```

How to do this with ActiveRecord? Maybe there's a different approach, but I was able to get it
to work via the magic of the `merge` method:
```ruby
base = Client.select("name, amount").joins(:address, :orders)
result = base.merge(Address.where(state: "TX"))
           .merge(base.where("orders.amount < ?", 40)
                    .or(base.where("orders.amount > ?", 100)))
           .order("orders.id")
```

We can extract some of the inner bits to try and make it clearer:
```ruby
base = Client.select("name, amount").joins(:address, :orders)
amounts = base.where("orders.amount < ?", 40).or(base.where("orders.amount > ?", 100))
texas_addresses = Address.where(state: "TX")
result = base.merge(texas_addresses).merge(amounts).order("orders.id")
```

And here's the SQL emitted:
```sql
SELECT name, amount
FROM "clients"
       INNER JOIN "addresses" ON "addresses"."client_id" = "clients"."id"
       INNER JOIN "orders" ON "orders"."client_id" = "clients"."id"
WHERE "addresses"."state" = "TX" AND ((orders.amount < 40) OR (orders.amount > 100))
ORDER BY orders.id
```
