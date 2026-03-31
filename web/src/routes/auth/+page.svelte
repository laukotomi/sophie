<div class="flex min-h-screen items-center justify-center p-4">
	<div class="w-full max-w-md space-y-6 card preset-tonal-surface p-8">
		<div class="space-y-1 text-center">
			<h1 class="text-2xl font-bold">Sign in</h1>
			<p class="text-sm text-surface-600-400">Enter your credentials to continue</p>
		</div>

		<form class="space-y-4" method="POST">
			<label class="block space-y-1">
				<span class="text-sm font-medium">Email</span>
				<input class="input" type="email" name="email" placeholder="you@example.com" required />
			</label>

			<label class="block space-y-1">
				<span class="text-sm font-medium">Password</span>
				<input class="input" type="password" name="password" placeholder="••••••••" required />
			</label>

			<button type="submit" class="btn w-full preset-filled-primary-500"> Sign in </button>
		</form>
	</div>
</div>
