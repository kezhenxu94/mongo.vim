// Seed data for tests and the demo: mongosh <uri> demo/seed.js
db = db.getSiblingDB('shop');
db.dropDatabase();

const cities = ['Berlin', 'Tokyo', 'Lisbon', 'Austin', 'Seoul'];
const users = [];
for (let i = 0; i < 25; i++) {
  users.push({
    name: `user${i}`,
    email: `user${i}@example.com`,
    age: 18 + ((i * 7) % 50),
    active: i % 3 !== 0,
    address: { city: cities[i % cities.length], zip: String(10000 + i) },
    tags: i % 2 ? ['vip'] : [],
    createdAt: new Date(Date.UTC(2026, 0, 1 + i)),
  });
}
const ids = db.users.insertMany(users).insertedIds;
db.users.createIndex({ email: 1 }, { unique: true });

db.products.insertMany([
  { sku: 'KB-01', title: 'Keyboard', price: NumberDecimal('49.90'), stock: 120 },
  { sku: 'MS-02', title: 'Mouse', price: NumberDecimal('19.90'), stock: 300 },
  { sku: 'MN-03', title: 'Monitor', price: NumberDecimal('219.00'), stock: 15 },
]);

const orders = [];
for (let i = 0; i < 60; i++) {
  orders.push({
    userId: ids[i % 25],
    items: [{ sku: ['KB-01', 'MS-02', 'MN-03'][i % 3], qty: 1 + (i % 4) }],
    total: 20 + ((i * 37) % 400),
    status: ['new', 'paid', 'shipped'][i % 3],
    createdAt: new Date(Date.UTC(2026, 1, 1 + (i % 28))),
  });
}
db.orders.insertMany(orders);

db = db.getSiblingDB('analytics');
db.dropDatabase();
db.events.insertMany([
  { type: 'click', page: '/home', at: new Date() },
  { type: 'view', page: '/cart', at: new Date() },
]);
