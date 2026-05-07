const { createCategory, listCategories, updateCategory } = require('../repositories/category-repository');

function slugify(value) {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

async function getCategories(activeOnly) {
  return listCategories(activeOnly);
}

async function addCategory({ name, description, icon }) {
  return createCategory({
    name,
    slug: slugify(name),
    description: description || '',
    icon: icon || 'briefcase-outline',
  });
}

async function editCategory({ id, name, description, icon, active }) {
  return updateCategory({
    id,
    name,
    slug: slugify(name),
    description: description || '',
    icon: icon || 'briefcase-outline',
    active,
  });
}

module.exports = {
  addCategory,
  editCategory,
  getCategories,
};
