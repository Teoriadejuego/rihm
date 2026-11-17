import { SOCIAL } from './contract.js';
export const visible = (cell) => Boolean(cell && !cell.suppressed && Number.isFinite(cell.percentage));
export const valueLabel = (cell) => !cell ? 'Unavailable' : visible(cell) ? `${cell.percentage.toFixed(1)}%` : 'Protected';
export const countLabel = (value) => value === null || value === undefined ? 'Protected' : value.toLocaleString('en-GB');
export const difference = (group, reference) => visible(group) && visible(reference) ? Math.round((group.percentage - reference.percentage) * 10) / 10 : null;
export const dateLabel = (value) => value ? `${new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }).format(new Date(value))} UTC` : 'Not yet published';
export function createModel(data, selection) {
  const countries = [...new Set(data.cells.filter((c) => c.scope === 'international').map((c) => c.country))]
    .sort((a, b) => a === 'All Countries' ? -1 : b === 'All Countries' ? 1 : a.localeCompare(b));
  const country = countries.includes(selection.country) ? selection.country : countries.includes('All Countries') ? 'All Countries' : countries[0] || '';
  const index = new Map(data.cells.map((cell) => [[cell.scope, cell.country, cell.gender, cell.behaviour].join('|'), cell]));
  const cell = (scope, behaviour) => index.get([scope, scope === 'class' ? 'Class' : country, selection.gender, behaviour].join('|'));
  const sample = (scope, field) => data.cells.find((row) => row.scope === scope && row.country === (scope === 'class' ? 'Class' : country) && row.gender === selection.gender && !row.suppressed && row[field] !== null)?.[field] ?? null;
  return { countries, country, cell, sample, selected: SOCIAL.filter((b) => selection.behaviours.has(b)) };
}
