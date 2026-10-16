// Resolve the optional PostgreSQL driver from the database test package,
// including when a suite lives in a sibling feature directory.
export async function loadPostgres() {
  return (await import('pg')).default;
}
