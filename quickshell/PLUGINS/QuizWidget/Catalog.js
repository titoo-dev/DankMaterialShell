.pragma library

var CATEGORIES = ["Technologies", "Concepts", "Méthodologies"];

var CATALOG = [
    // Technologies
    { id: "js", label: "JavaScript / TypeScript", category: "Technologies" },
    { id: "python", label: "Python", category: "Technologies" },
    { id: "go", label: "Go", category: "Technologies" },
    { id: "rust", label: "Rust", category: "Technologies" },
    { id: "java", label: "Java / JVM", category: "Technologies" },
    { id: "react", label: "React", category: "Technologies" },
    { id: "node", label: "Node.js", category: "Technologies" },
    { id: "sql", label: "SQL / PostgreSQL", category: "Technologies" },
    { id: "docker", label: "Docker", category: "Technologies" },
    { id: "kubernetes", label: "Kubernetes", category: "Technologies" },
    { id: "linux", label: "Linux / shell", category: "Technologies" },
    { id: "git", label: "Git", category: "Technologies" },
    { id: "cloud", label: "Cloud (AWS/GCP/Azure)", category: "Technologies" },
    // Concepts
    { id: "algorithms", label: "Algorithmes & complexité", category: "Concepts" },
    { id: "datastructures", label: "Structures de données", category: "Concepts" },
    { id: "oop", label: "Programmation orientée objet", category: "Concepts" },
    { id: "fp", label: "Programmation fonctionnelle", category: "Concepts" },
    { id: "networking", label: "Réseaux (TCP/IP, HTTP)", category: "Concepts" },
    { id: "security", label: "Sécurité (web, crypto)", category: "Concepts" },
    { id: "concurrency", label: "Concurrence & parallélisme", category: "Concepts" },
    { id: "databases", label: "Bases de données & modélisation", category: "Concepts" },
    { id: "os", label: "Systèmes d'exploitation", category: "Concepts" },
    { id: "patterns", label: "Design patterns", category: "Concepts" },
    { id: "architecture", label: "Architecture (REST, microservices)", category: "Concepts" },
    // Méthodologies
    { id: "agile", label: "Agile / Scrum", category: "Méthodologies" },
    { id: "tdd", label: "Tests & TDD", category: "Méthodologies" },
    { id: "cicd", label: "CI/CD", category: "Méthodologies" },
    { id: "devops", label: "DevOps", category: "Méthodologies" },
    { id: "gitflow", label: "Workflow Git (branching)", category: "Méthodologies" },
    { id: "codereview", label: "Revue de code", category: "Méthodologies" },
    { id: "cleancode", label: "Clean code / refactoring", category: "Méthodologies" }
];

function allCategories() {
    return CATEGORIES.slice();
}

function topicById(id) {
    for (var i = 0; i < CATALOG.length; i++) {
        if (CATALOG[i].id === id) return CATALOG[i];
    }
    return null;
}

function topicsByCategory(category) {
    var out = [];
    for (var i = 0; i < CATALOG.length; i++) {
        if (CATALOG[i].category === category) out.push(CATALOG[i]);
    }
    return out;
}

function categoriesWithTopics() {
    var out = [];
    for (var c = 0; c < CATEGORIES.length; c++) {
        out.push({ category: CATEGORIES[c], topics: topicsByCategory(CATEGORIES[c]) });
    }
    return out;
}
