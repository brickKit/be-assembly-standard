[English](0005-no-java-or-csharp.md) · [中文](../../../zh/02-decisions/01-architecture/0005-no-java-or-csharp.md)

# 0005 No Java or C#

## Decision

Backend components are written in Go or Python; TypeScript is used only for the mobile BFF and the frontend. No component is written in Java, Kotlin, C# or another JVM / .NET language.

## Why

Customers deploy the system on a single machine of their own, and the memory and start-up cost of a JVM or CLR per component conflicts with that directly. Every language also needs its own SDK, shell launcher and stack row ([0003](0003-locked-stack-per-language.md)); a new language multiplies that work for every component written in it.

## What this rules out

- "Write this component in Spring Boot / .NET, it has a better library for X"
- Kotlin, Scala or other JVM languages
- A fourth backend language added for one component

## Revisit only if

The deployment target stops being a single customer machine and a required capability exists only in that ecosystem. Even then the language comes in with an SDK, a shell launcher and a stack row first, not with one component.
