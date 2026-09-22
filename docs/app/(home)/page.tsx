import Link from 'next/link';

export default function HomePage() {
  return (
    <main className="flex flex-col justify-center items-center text-center flex-1 px-4 py-16">
      <h1 className="text-4xl font-bold mb-4">Air</h1>
      <p className="text-fd-muted-foreground max-w-md mb-8">
        A web framework for Bend: routing, middleware, sessions, validation, templates and
        static files, over HTTP/1.1.
      </p>
      <div className="flex gap-3">
        <Link
          href="/docs"
          className="rounded-full bg-fd-primary px-5 py-2 text-sm font-medium text-fd-primary-foreground"
        >
          Get started
        </Link>
        <Link
          href="https://github.com/victor-teles/air-bend"
          className="rounded-full border px-5 py-2 text-sm font-medium"
        >
          GitHub
        </Link>
      </div>
    </main>
  );
}
