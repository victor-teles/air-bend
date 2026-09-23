import Image from 'next/image';
import Link from 'next/link';
import banner from '@/public/banner.png';

export default function HomePage() {
  return (
    <main className="flex flex-col items-center text-center flex-1 px-4 py-12">
      <h1 className="sr-only">Air Bend</h1>
      <Image
        src={banner}
        alt="Air Bend"
        priority
        placeholder="blur"
        sizes="(min-width: 768px) 672px, 100vw"
        className="w-full max-w-2xl"
      />
      <p className="text-fd-muted-foreground text-lg max-w-xl mt-8 mb-8 text-pretty">
        A web framework for Bend: routing, middleware, sessions, validation, templates and
        static files, over HTTP/1.1.
      </p>
      <div className="flex gap-3">
        <Link
          href="/docs"
          className="rounded-full bg-fd-primary px-5 py-2 text-sm font-medium text-fd-primary-foreground transition-opacity hover:opacity-90"
        >
          Get started
        </Link>
        <Link
          href="https://github.com/victor-teles/air-bend"
          className="rounded-full border bg-fd-background/60 px-5 py-2 text-sm font-medium transition-colors hover:bg-fd-accent"
        >
          GitHub
        </Link>
      </div>
    </main>
  );
}
