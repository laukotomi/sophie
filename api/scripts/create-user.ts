/// <reference types="node" />
import { auth } from '../src/auth.js';
import * as readline from 'node:readline';

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

rl.question('Email: ', (email) => {
    rl.question('Password: ', (password) => {
        rl.question('Name: ', (name) => {
            rl.close();

            auth.api.signUpEmail({ body: { email, password, name } }).then((response) => {
                console.log(`User created: ${response.user.email} (id: ${response.user.id})`);
                process.exit(0);
            }).catch((err: unknown) => {
                console.error('Failed to create user:', err);
                process.exit(1);
            });
        });
    });
});
